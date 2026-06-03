package service

import (
	"crypto/sha256"
	"errors"
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

type AuthService struct {
	db          *gorm.DB
	cfg         *config.Config
	srpParams   *auth.SRPParams
	srpSessions map[string]*auth.SRPServer
	srpMu       sync.Mutex
}

func NewAuthService(db *gorm.DB, cfg *config.Config) *AuthService {
	return &AuthService{
		db:          db,
		cfg:         cfg,
		srpParams:   auth.NewSRPParams(),
		srpSessions: make(map[string]*auth.SRPServer),
	}
}

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

// InitiateSRP starts the SRP authentication flow.
// Returns salt + B (server's public ephemeral).
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

	s.srpMu.Lock()
	s.srpSessions[username] = srv
	s.srpMu.Unlock()

	return user.SRPSalt, B, nil
}

// VerifySRP verifies the client proof and returns the server proof + JWT token.
func (s *AuthService) VerifySRP(username string, A, M1 []byte) (M2 []byte, token string, err error) {
	var user model.User
	if err := s.db.Where("username = ?", username).First(&user).Error; err != nil {
		return nil, "", errors.New("user not found")
	}

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

func (s *AuthService) generateToken(user *model.User) (string, error) {
	claims := &model.Claims{
		UserID:   user.ID,
		Username: user.Username,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(72 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(s.cfg.JWTSecret))
}

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

// computeSRPX calculates x = SHA256(salt || SHA256(username || ":" || password))
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
