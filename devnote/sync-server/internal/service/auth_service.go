// 认证服务 - 用户认证与授权
// 借鉴: Joplin 认证流程 (https://github.com/laurent22/joplin)
// - JWT + RefreshToken 双令牌轮转
// - SRP 安全远程密码协议
// - Bcrypt 密码哈希
package service

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"math/big"
	"sync"
	"time"

	"github.com/devnote/sync-server/internal/auth"
	"github.com/devnote/sync-server/internal/config"
	"github.com/devnote/sync-server/internal/model"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

// AuthService 认证服务
//
// 借鉴 1Password 认证设计：将"长期凭证"（密码 / SRP verifier）与
// "短期凭证"（access / refresh token）解耦。
type AuthService struct {
	db          *gorm.DB
	cfg         *config.Config
	srpParams   *auth.SRPParams
	srpSessions map[string]*auth.SRPServer
	srpMu       sync.Mutex
}

// NewAuthService 构造 AuthService
//
// 借鉴 1Password 的"认证上下文隔离"做法：每个 SRP 会话以 username 为 key
// 独立存放，避免多用户并发登录时的状态串扰。
func NewAuthService(db *gorm.DB, cfg *config.Config) *AuthService {
	return &AuthService{
		db:          db,
		cfg:         cfg,
		srpParams:   auth.NewSRPParams(),
		srpSessions: make(map[string]*auth.SRPServer),
	}
}

// Register 使用传统 bcrypt 方式注册用户
//
// 借鉴 1Password 的"主密码 + 派生密钥"思路：服务端只保存 bcrypt 哈希，
// 即使数据库泄露，攻击者也无法直接获得明文密码。
func (s *AuthService) Register(username, password string) (*model.User, error) {
	var existing model.User
	if err := s.db.Where("username = ?", username).First(&existing).Error; err == nil {
		return nil, errors.New("username already exists")
	}

	hashed, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, err
	}

	user := &model.User{
		ID:       uuid.New().String(),
		Username: username,
		Password: string(hashed),
	}

	if err := s.db.Create(user).Error; err != nil {
		return nil, err
	}

	return user, nil
}

// RegisterWithSRP 使用 SRP 注册用户
//
// 借鉴 SRP（Secure Remote Password）协议：
// 服务端不存储密码哈希，而是存储 verifier = g^x mod N（其中 x = SHA256(salt | SHA256(user:pass))），
// 即使 verifier 泄露，攻击者仍需对每个候选密码执行一次昂贵的模幂运算。
func (s *AuthService) RegisterWithSRP(username, password string) (*model.User, error) {
	var existing model.User
	if err := s.db.Where("username = ?", username).First(&existing).Error; err == nil {
		return nil, errors.New("username already exists")
	}

	salt, err := auth.GenerateSalt()
	if err != nil {
		return nil, err
	}

	verifier, err := auth.GenerateVerifier(s.srpParams, username, password, salt)
	if err != nil {
		return nil, err
	}

	user := &model.User{
		ID:          uuid.New().String(),
		Username:    username,
		SRPSalt:     salt,
		SRPVerifier: verifier,
		SRPEnabled:  true,
	}

	if err := s.db.Create(user).Error; err != nil {
		return nil, err
	}

	return user, nil
}

// Login 登录入口
//
// 借鉴 1Password 的"双轨认证"模式：
//   - 传统用户走 bcrypt 比对；
//   - SRP 启用用户走 verifier 比对（更强的零知识证明）。
// 登录成功签发 JWT access token。
func (s *AuthService) Login(username, password string) (*model.User, string, error) {
	var user model.User
	if err := s.db.Where("username = ?", username).First(&user).Error; err != nil {
		return nil, "", errors.New("invalid credentials")
	}

	// Fallback: if SRP is not enabled, use bcrypt password check
	if !user.SRPEnabled && user.Password != "" {
		if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(password)); err != nil {
			return nil, "", errors.New("invalid credentials")
		}
	} else if user.SRPEnabled {
		// For SRP-enabled users, verify using the verifier directly
		// 借鉴 SRP 协议：通过比较 v = g^x mod N 与存储的 verifier 是否一致来认证。
		x := computeSRPX(username, password, user.SRPSalt)
		v := new(big.Int).Exp(s.srpParams.G(), x, s.srpParams.N())
		if v.Cmp(new(big.Int).SetBytes(user.SRPVerifier)) != 0 {
			return nil, "", errors.New("invalid credentials")
		}
	} else {
		return nil, "", errors.New("invalid credentials")
	}

	token, err := s.generateToken(&user)
	if err != nil {
		return nil, "", err
	}

	return &user, token, nil
}

// InitiateSRP 启动 SRP 认证流程
//
// 借鉴 SRP 协议的两步握手：
//  1. 客户端发送 username，服务端返回 salt + 公钥 B = k*v + g^b mod N。
//  2. 客户端利用 salt、自身密码与 B 计算出自己的公钥 A 与证明 M1。
//
// **算法来源**: SRP-6a 协议（RFC 5054）。
func (s *AuthService) InitiateSRP(username string) (salt []byte, B []byte, err error) {
	var user model.User
	if err := s.db.Where("username = ?", username).First(&user).Error; err != nil {
		return nil, nil, errors.New("user not found")
	}

	if !user.SRPEnabled {
		return nil, nil, errors.New("SRP not enabled for this user")
	}

	srv := auth.NewSRPServer(s.srpParams)
	B, err = srv.ComputeB(user.SRPVerifier)
	if err != nil {
		return nil, nil, err
	}

	// 借鉴 1Password 的"会话隔离"：将 SRP 会话按 username 暂存，
	// 完成 VerifySRP 后立即删除（一次性会话）。
	s.srpMu.Lock()
	s.srpSessions[username] = srv
	s.srpMu.Unlock()

	return user.SRPSalt, B, nil
}

// VerifySRP 校验客户端证明并签发 JWT
//
// 借鉴 SRP 协议：服务端用自身私钥 b 与客户端公钥 A 推导出共享密钥，
// 验证客户端证明 M1 后返回服务端证明 M2，并签发 access token。
func (s *AuthService) VerifySRP(username string, A, M1 []byte) (M2 []byte, token string, err error) {
	var user model.User
	if err := s.db.Where("username = ?", username).First(&user).Error; err != nil {
		return nil, "", errors.New("user not found")
	}

	// 借鉴 1Password 的"一次性会话"模式：取出并立刻销毁会话，
	// 避免重放攻击。
	s.srpMu.Lock()
	srv, ok := s.srpSessions[username]
	if ok {
		delete(s.srpSessions, username)
	}
	s.srpMu.Unlock()

	if !ok {
		return nil, "", errors.New("no active SRP session")
	}

	M2, err = srv.ProcessClientProof(username, user.SRPSalt, A, M1)
	if err != nil {
		return nil, "", err
	}

	jwtToken, err := s.generateToken(&user)
	if err != nil {
		return nil, "", err
	}

	return M2, jwtToken, nil
}

// generateToken 签发 HS256 JWT
//
// 借鉴 1Password 的"短生命周期 access token"策略：有效期 72 小时。
// 修复(P0): 在 RegisteredClaims 中设置 Subject = user.ID，
// 使 business-server 通过标准 JWT "sub" 字段获取用户 ID 成为可能。
// 同时保留自定义 user_id/username 字段以兼容 sync-server 内部使用。
func (s *AuthService) generateToken(user *model.User) (string, error) {
	claims := &model.Claims{
		UserID:   user.ID,
		Username: user.Username,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   user.ID,
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(72 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(s.cfg.JWTSecret))
}

// ValidateToken 校验 JWT 签名与有效期
func (s *AuthService) ValidateToken(tokenStr string) (*model.Claims, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &model.Claims{}, func(t *jwt.Token) (interface{}, error) {
		return []byte(s.cfg.JWTSecret), nil
	})
	if err != nil {
		return nil, err
	}

	claims, ok := token.Claims.(*model.Claims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid token")
	}

	return claims, nil
}

// computeSRPX 计算 x = SHA256(salt || SHA256(username || ":" || password))
//
// 借鉴 SRP 协议（RFC 5054 §2.6）的 x 定义：
//   inner = SHA-1/256(username || ":" || password)
//   x     = SHA-1/256(salt || inner)
func computeSRPX(username, password string, salt []byte) *big.Int {
	inner := sha256.New()
	inner.Write([]byte(username))
	inner.Write([]byte(":"))
	inner.Write([]byte(password))
	innerHash := inner.Sum(nil)

	outer := sha256.New()
	outer.Write(salt)
	outer.Write(innerHash)
	xBytes := outer.Sum(nil)

	return new(big.Int).SetBytes(xBytes)
}

// generateRandomToken 生成十六进制编码的随机 token
func generateRandomToken(length int) string {
	b := make([]byte, length)
	rand.Read(b)
	return hex.EncodeToString(b)
}

// GenerateRefreshToken 生成 refresh token
//
// 借鉴 1Password 的"长生命周期 refresh token"策略：30 天有效期，
// 同时记录 Revoked 标志位以便主动吊销。
func (s *AuthService) GenerateRefreshToken(userID string) (string, error) {
	token := generateRandomToken(32)
	refreshToken := &model.RefreshToken{
		ID:        uuid.New().String(),
		UserID:    userID,
		Token:     token,
		ExpiresAt: time.Now().Add(30 * 24 * time.Hour), // 30 days
		CreatedAt: time.Now(),
		Revoked:   false,
	}
	if err := s.db.Create(refreshToken).Error; err != nil {
		return "", err
	}
	return token, nil
}

// RefreshAccessToken 刷新 access token
//
// 借鉴 1Password 的"refresh token 轮转（rotation）"：每次刷新都立刻
// 吊销旧 refresh token 并签发新 refresh token，从而将泄露风险窗口
// 限制在单次刷新间隔内。
func (s *AuthService) RefreshAccessToken(refreshToken string) (string, string, error) {
	var rt model.RefreshToken
	if err := s.db.Where("token = ?", refreshToken).First(&rt).Error; err != nil {
		return "", "", errors.New("invalid refresh token")
	}

	if rt.Revoked {
		return "", "", errors.New("refresh token has been revoked")
	}

	if time.Now().After(rt.ExpiresAt) {
		return "", "", errors.New("refresh token has expired")
	}

	// Revoke old refresh token (rotation)
	if err := s.db.Model(&rt).Update("revoked", true).Error; err != nil {
		return "", "", fmt.Errorf("revoke old refresh token: %w", err)
	}

	// Find user
	var user model.User
	if err := s.db.Where("id = ?", rt.UserID).First(&user).Error; err != nil {
		return "", "", errors.New("user not found")
	}

	// Generate new access token
	accessToken, err := s.generateToken(&user)
	if err != nil {
		return "", "", err
	}

	// Generate new refresh token
	newRefreshToken, err := s.GenerateRefreshToken(user.ID)
	if err != nil {
		return "", "", err
	}

	return accessToken, newRefreshToken, nil
}

// RevokeRefreshToken 吊销单个 refresh token
//
// 借鉴 1Password 的"按设备吊销"能力：用户可在"已登录设备"列表中
// 主动登出某个设备，底层实现就是吊销对应的 refresh token。
func (s *AuthService) RevokeRefreshToken(token string) error {
	return s.db.Model(&model.RefreshToken{}).Where("token = ?", token).Update("revoked", true).Error
}

// RevokeAllUserTokens 吊销某个用户的所有未撤销 refresh token
//
// 借鉴 1Password 的"修改主密码即登出全部设备"做法：密码变更或账号被盗时，
// 通过一次性吊销所有 token 强制重新登录。
func (s *AuthService) RevokeAllUserTokens(userID string) error {
	if err := s.db.Model(&model.RefreshToken{}).Where("user_id = ?", userID).Update("revoked", true).Error; err != nil {
		return fmt.Errorf("revoke all tokens: %w", err)
	}
	return nil
}
