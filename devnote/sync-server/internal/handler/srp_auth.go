package handler

import (
	"encoding/base64"
	"net/http"

	"github.com/devnote/sync-server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// SRPAuthHandler handles SRP zero-knowledge authentication endpoints.
type SRPAuthHandler struct {
	authService *service.AuthService
	logger      *zap.Logger
}

// NewSRPAuthHandler creates a new SRP auth handler.
func NewSRPAuthHandler(authService *service.AuthService, logger *zap.Logger) *SRPAuthHandler {
	if logger == nil {
		logger = zap.NewNop()
	}
	return &SRPAuthHandler{authService: authService, logger: logger}
}

// SRPRegisterRequest represents the request to register with SRP.
type SRPRegisterRequest struct {
	Username string `json:"username" binding:"required,min=3,max=64"`
	Password string `json:"password" binding:"required,min=6"`
}

// SRPInitRequest represents the request to initiate SRP authentication.
type SRPInitRequest struct {
	Username string `json:"username" binding:"required"`
}

// SRPInitResponse represents the server's response to SRP initiation.
type SRPInitResponse struct {
	Salt string `json:"salt"`
	B    string `json:"B"`
}

// SRPVerifyRequest represents the client's proof submission.
type SRPVerifyRequest struct {
	Username string `json:"username" binding:"required"`
	A        string `json:"A" binding:"required"`
	M1       string `json:"M1" binding:"required"`
}

// SRPVerifyResponse represents the server's proof + session token.
type SRPVerifyResponse struct {
	M2       string `json:"M2"`
	Token    string `json:"token"`
	UserID   string `json:"user_id"`
	Username string `json:"username"`
}

// Register handles SRP-based user registration.
// POST /api/v1/auth/srp/register
func (h *SRPAuthHandler) Register(c *gin.Context) {
	var req SRPRegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.authService.RegisterWithSRP(req.Username, req.Password)
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"id":          user.ID,
		"username":    user.Username,
		"srp_enabled": true,
	})
}

// Init handles SRP authentication initiation.
// POST /api/v1/auth/srp/init
func (h *SRPAuthHandler) Init(c *gin.Context) {
	var req SRPInitRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	salt, B, err := h.authService.InitiateSRP(req.Username)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, SRPInitResponse{
		Salt: base64.StdEncoding.EncodeToString(salt),
		B:    base64.StdEncoding.EncodeToString(B),
	})
}

// Verify handles SRP client proof verification.
// POST /api/v1/auth/srp/verify
func (h *SRPAuthHandler) Verify(c *gin.Context) {
	var req SRPVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ABytes, err := base64.StdEncoding.DecodeString(req.A)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid A encoding"})
		return
	}

	M1Bytes, err := base64.StdEncoding.DecodeString(req.M1)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid M1 encoding"})
		return
	}

	M2, token, err := h.authService.VerifySRP(req.Username, ABytes, M1Bytes)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, SRPVerifyResponse{
		M2:    base64.StdEncoding.EncodeToString(M2),
		Token: token,
	})
}
