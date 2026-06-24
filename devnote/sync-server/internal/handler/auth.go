package handler

import (
	"net/http"

	"github.com/devnote/sync-server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type AuthHandler struct {
	authService *service.AuthService
	logger      *zap.Logger
}

func NewAuthHandler(authService *service.AuthService, logger *zap.Logger) *AuthHandler {
	if logger == nil {
		logger = zap.NewNop()
	}
	return &AuthHandler{authService: authService, logger: logger}
}

type RegisterRequest struct {
	Username string `json:"username" binding:"required,min=3,max=64"`
	Password string `json:"password" binding:"required,min=6"`
}

type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.authService.Register(req.Username, req.Password)
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"id":       user.ID,
		"username": user.Username,
	})
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, token, err := h.authService.Login(req.Username, req.Password)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Generate refresh token
	refreshToken, err := h.authService.GenerateRefreshToken(user.ID)
	if err != nil {
		respondInternalError(c, h.logger, "failed to generate refresh token", err)
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":            user.ID,
		"username":      user.Username,
		"token":         token,
		"refresh_token": refreshToken,
		"expires_in":    1800, // 30 分钟，与 auth_service.go 的 accessTokenTTL 一致
	})
}

func (h *AuthHandler) RefreshToken(c *gin.Context) {
	var req struct {
		RefreshToken string `json:"refresh_token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	accessToken, newRefreshToken, err := h.authService.RefreshAccessToken(req.RefreshToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"access_token":  accessToken,
		"refresh_token": newRefreshToken,
		"expires_in":    1800, // 30 分钟，与 auth_service.go 的 accessTokenTTL 一致
	})
}

func (h *AuthHandler) Logout(c *gin.Context) {
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}
	c.ShouldBindJSON(&req)
	if req.RefreshToken != "" {
		// P3 修复 (P3-15): 原实现忽略 RevokeRefreshToken 错误，无论撤销是否成功都返回成功
		// 现改为检查错误并记录日志，便于审计；token 通常有自然过期时间，不阻断登出流程
		if err := h.authService.RevokeRefreshToken(req.RefreshToken); err != nil {
			h.logger.Error("revoke refresh token failed during logout", zap.Error(err))
		}
	}
	c.JSON(http.StatusOK, gin.H{"message": "logged out"})
}
