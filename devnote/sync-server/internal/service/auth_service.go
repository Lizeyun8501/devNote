// 认证服务 - 用户认证与授权
// 借鉴: Joplin 认证流程 (https://github.com/laurent22/joplin)
// - JWT + RefreshToken 双令牌轮转
// - SRP 安全远程密码协议
// - Bcrypt 密码哈希
package service

import (
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
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
	"github.com/jmoiron/sqlx"
	"golang.org/x/crypto/bcrypt"
)

// AuthService 认证服务
//
// 借鉴 1Password 认证设计：将"长期凭证"（密码 / SRP verifier）与
// "短期凭证"（access / refresh token）解耦。
type AuthService struct {
	db          *sqlx.DB
	cfg         *config.Config
	srpParams   *auth.SRPParams
	srpSessions map[string]*srpSessionEntry
	srpMu       sync.Mutex
}

// srpSessionEntry 包装 SRP 会话及其创建时间，用于实现 TTL 过期清理。
type srpSessionEntry struct {
	server    *auth.SRPServer
	createdAt time.Time
}

// SRP 会话生命周期相关常量
const (
	// srpSessionTTL 单个 SRP 会话的最大有效时长，超过后 VerifySRP 将拒绝。
	srpSessionTTL = 5 * time.Minute
	// srpSessionCleanupInterval 后台清理 goroutine 的扫描间隔。
	srpSessionCleanupInterval = 5 * time.Minute
	// srpSessionMaxAge 后台清理时删除超过此时长的会话。
	srpSessionMaxAge = 10 * time.Minute
)

// NewAuthService 构造 AuthService
//
// 借鉴 1Password 的"认证上下文隔离"做法：每个 SRP 会话以 username 为 key
// 独立存放，避免多用户并发登录时的状态串扰。
func NewAuthService(db *sqlx.DB, cfg *config.Config) *AuthService {
	s := &AuthService{
		db:          db,
		cfg:         cfg,
		srpParams:   auth.NewSRPParams(),
		srpSessions: make(map[string]*srpSessionEntry),
	}
	go s.cleanupSRPSessions()
	return s
}

// cleanupSRPSessions 后台定期清理过期的 SRP 会话，防止 map 无限增长。
func (s *AuthService) cleanupSRPSessions() {
	ticker := time.NewTicker(srpSessionCleanupInterval)
	defer ticker.Stop()
	for range ticker.C {
		s.srpMu.Lock()
		now := time.Now()
		for k, v := range s.srpSessions {
			if now.Sub(v.createdAt) > srpSessionMaxAge {
				delete(s.srpSessions, k)
			}
		}
		s.srpMu.Unlock()
	}
}

// Register 使用传统 bcrypt 方式注册用户
//
// 借鉴 1Password 的"主密码 + 派生密钥"思路：服务端只保存 bcrypt 哈希，
// 即使数据库泄露，攻击者也无法直接获得明文密码。
func (s *AuthService) Register(username, password string) (*model.User, error) {
	var existing model.User
	err := s.db.Get(&existing, `SELECT id FROM users WHERE username = ?`, username)
	if err == nil {
		return nil, errors.New("username already exists")
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return nil, fmt.Errorf("query user: %w", err)
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

	_, err = s.db.Exec(
		`INSERT INTO users (id, username, password, srp_enabled, created_at, updated_at) VALUES (?, ?, ?, 0, ?, ?)`,
		user.ID, user.Username, user.Password, time.Now(), time.Now(),
	)
	if err != nil {
		return nil, fmt.Errorf("create user: %w", err)
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
	err := s.db.Get(&existing, `SELECT id FROM users WHERE username = ?`, username)
	if err == nil {
		return nil, errors.New("username already exists")
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return nil, fmt.Errorf("query user: %w", err)
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

	_, err = s.db.Exec(
		`INSERT INTO users (id, username, srp_salt, srp_verifier, srp_enabled, created_at, updated_at) VALUES (?, ?, ?, ?, 1, ?, ?)`,
		user.ID, user.Username, user.SRPSalt, user.SRPVerifier, time.Now(), time.Now(),
	)
	if err != nil {
		return nil, fmt.Errorf("create user: %w", err)
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
	err := s.db.Get(&user, `SELECT * FROM users WHERE username = ? AND deleted_at IS NULL`, username)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, "", errors.New("invalid credentials")
		}
		return nil, "", fmt.Errorf("query user: %w", err)
	}

	// Fallback: if SRP is not enabled, use bcrypt password check
	if !user.SRPEnabled && user.Password != "" {
		if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(password)); err != nil {
			return nil, "", errors.New("invalid credentials")
		}
	} else if user.SRPEnabled {
		return nil, "", errors.New("SRP-enabled accounts must use /auth/srp/init and /auth/srp/verify endpoints")
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
	err = s.db.Get(&user, `SELECT * FROM users WHERE username = ? AND deleted_at IS NULL`, username)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil, errors.New("user not found")
		}
		return nil, nil, fmt.Errorf("query user: %w", err)
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
	s.srpSessions[username] = &srpSessionEntry{
		server:    srv,
		createdAt: time.Now(),
	}
	s.srpMu.Unlock()

	return user.SRPSalt, B, nil
}

// VerifySRP 校验客户端证明并签发 JWT
//
// 借鉴 SRP 协议：服务端用自身私钥 b 与客户端公钥 A 推导出共享密钥，
// 验证客户端证明 M1 后返回服务端证明 M2，并签发 access token。
func (s *AuthService) VerifySRP(username string, A, M1 []byte) (M2 []byte, token string, err error) {
	var user model.User
	err = s.db.Get(&user, `SELECT * FROM users WHERE username = ? AND deleted_at IS NULL`, username)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, "", errors.New("user not found")
		}
		return nil, "", fmt.Errorf("query user: %w", err)
	}

	// 借鉴 1Password 的"一次性会话"模式：取出并立刻销毁会话，
	// 避免重放攻击。
	s.srpMu.Lock()
	entry, ok := s.srpSessions[username]
	if ok {
		delete(s.srpSessions, username)
	}
	s.srpMu.Unlock()

	if !ok {
		return nil, "", errors.New("no active SRP session")
	}

	// 检查会话是否过期，防止陈旧会话被利用
	if time.Since(entry.createdAt) > srpSessionTTL {
		return nil, "", errors.New("session expired")
	}

	srv := entry.server
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
// 借鉴 1Password 的"短生命周期 access token"策略。
// P0 修复: 原有效期 72 小时过长（行业标准 15-30 分钟），一旦泄露攻击窗口巨大。
// 现改为 30 分钟，依赖 refresh token 续期。
// 同时添加 iss/aud/jti 声明，支持签发方/受众校验和 token 吊销。
func (s *AuthService) generateToken(user *model.User) (string, error) {
	claims := &model.Claims{
		UserID:   user.ID,
		Username: user.Username,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   user.ID,
			Issuer:    "devnote-sync-server",
			Audience:  []string{"devnote-client", "devnote-business-server"},
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(30 * time.Minute)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			ID:        uuid.New().String(),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(s.cfg.JWTSecret))
}

// ValidateToken 校验 JWT 签名、有效期与受众
// P0 修复: 增加 iss/aud 校验，防止跨服务 token 重用
func (s *AuthService) ValidateToken(tokenStr string) (*model.Claims, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &model.Claims{}, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, jwt.ErrSignatureInvalid
		}
		return []byte(s.cfg.JWTSecret), nil
	}, jwt.WithIssuer("devnote-sync-server"), jwt.WithAudience("devnote-client"))
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
func generateRandomToken(length int) (string, error) {
	b := make([]byte, length)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generate random token: %w", err)
	}
	return hex.EncodeToString(b), nil
}

// GenerateRefreshToken 生成 refresh token
//
// 借鉴 1Password 的"长生命周期 refresh token"策略：30 天有效期，
// 同时记录 Revoked 标志位以便主动吊销。
// P0 修复: 原实现明文存储 token，数据库泄露后可直接使用。
// 现改为存储 SHA-256 哈希，查询时哈希后比对。
func (s *AuthService) GenerateRefreshToken(userID string) (string, error) {
	token, err := generateRandomToken(32)
	if err != nil {
		return "", err
	}
	tokenHash := hashToken(token)
	now := time.Now()
	_, err = s.db.Exec(
		`INSERT INTO refresh_tokens (id, user_id, token, expires_at, created_at, revoked) VALUES (?, ?, ?, ?, ?, 0)`,
		uuid.New().String(), userID, tokenHash, now.Add(30*24*time.Hour), now,
	)
	if err != nil {
		return "", fmt.Errorf("create refresh token: %w", err)
	}
	return token, nil
}

// hashToken 计算 token 的 SHA-256 十六进制哈希
// P0 修复: Refresh Token 不再明文存储
func hashToken(token string) string {
	h := sha256.Sum256([]byte(token))
	return hex.EncodeToString(h[:])
}

// RefreshAccessToken 刷新 access token
//
// 借鉴 1Password 的"refresh token 轮转（rotation）"：每次刷新都立刻
// 吊销旧 refresh token 并签发新 refresh token，从而将泄露风险窗口
// 限制在单次刷新间隔内。
func (s *AuthService) RefreshAccessToken(refreshToken string) (string, string, error) {
	var rt model.RefreshToken
	err := s.db.Get(&rt, `SELECT * FROM refresh_tokens WHERE token = ?`, hashToken(refreshToken))
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", "", errors.New("invalid refresh token")
		}
		return "", "", fmt.Errorf("query refresh token: %w", err)
	}

	if rt.Revoked {
		return "", "", errors.New("refresh token has been revoked")
	}

	if time.Now().After(rt.ExpiresAt) {
		return "", "", errors.New("refresh token has expired")
	}

	// Revoke old refresh token (rotation)
	_, err = s.db.Exec(`UPDATE refresh_tokens SET revoked = 1 WHERE id = ?`, rt.ID)
	if err != nil {
		return "", "", fmt.Errorf("revoke old refresh token: %w", err)
	}

	// Find user
	var user model.User
	err = s.db.Get(&user, `SELECT * FROM users WHERE id = ? AND deleted_at IS NULL`, rt.UserID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", "", errors.New("user not found")
		}
		return "", "", fmt.Errorf("query user: %w", err)
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
//
// P0 修复 (SEC-01): 原实现用明文 token 查询，但 GenerateRefreshToken
// 存储的是 SHA-256 哈希，导致永远查不到记录，吊销静默失败。
// 现改为哈希后查询，与存储逻辑一致。
func (s *AuthService) RevokeRefreshToken(token string) error {
	tokenHash := hashToken(token)
	result, err := s.db.Exec(`UPDATE refresh_tokens SET revoked = 1 WHERE token = ?`, tokenHash)
	if err != nil {
		return fmt.Errorf("revoke refresh token: %w", err)
	}
	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		return errors.New("refresh token not found or already revoked")
	}
	return nil
}

// RevokeAllUserTokens 吊销某个用户的所有未撤销 refresh token
//
// 借鉴 1Password 的"修改主密码即登出全部设备"做法：密码变更或账号被盗时，
// 通过一次性吊销所有 token 强制重新登录。
func (s *AuthService) RevokeAllUserTokens(userID string) error {
	_, err := s.db.Exec(`UPDATE refresh_tokens SET revoked = 1 WHERE user_id = ?`, userID)
	if err != nil {
		return fmt.Errorf("revoke all tokens: %w", err)
	}
	return nil
}
