package handler

import (
	"net/http"
	"time"

	"github.com/devnote/sync-server/internal/service"
	"github.com/gin-gonic/gin"
)

type ShareHandler struct {
	shareService *service.ShareService
}

func NewShareHandler(shareService *service.ShareService) *ShareHandler {
	return &ShareHandler{shareService: shareService}
}

type CreateShareRequest struct {
	NoteID    string `json:"note_id" binding:"required"`
	Title     string `json:"title" binding:"required"`
	Content   string `json:"content" binding:"required"`
	Password  string `json:"password"`
	ExpiresIn int64  `json:"expires_in"` // 秒数，0 表示永不过期
}

// CreateShare 创建分享
func (h *ShareHandler) CreateShare(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user_id not found in context"})
		return
	}

	var req CreateShareRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var expiresAt *time.Time
	if req.ExpiresIn > 0 {
		t := time.Now().Add(time.Duration(req.ExpiresIn) * time.Second)
		expiresAt = &t
	}

	share, err := h.shareService.CreateShare(userID, req.NoteID, req.Title, req.Content, req.Password, expiresAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":           share.ID,
		"share_token":  share.ShareToken,
		"share_url":    "/s/" + share.ShareToken,
		"has_password": share.HasPassword,
		"expires_at":   share.ExpiresAt,
		"created_at":   share.CreatedAt,
	})
}

// ListShares 列出用户的分享
func (h *ShareHandler) ListShares(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user_id not found in context"})
		return
	}

	shares, err := h.shareService.ListUserShares(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"shares": shares})
}

// DeleteShare 删除分享
func (h *ShareHandler) DeleteShare(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user_id not found in context"})
		return
	}
	shareID := c.Param("shareId")

	if err := h.shareService.DeleteShare(userID, shareID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "deleted"})
}

// GetSharedNote 公开访问分享的笔记（无需认证）
func (h *ShareHandler) GetSharedNote(c *gin.Context) {
	token := c.Param("token")
	password := c.Query("password")

	share, err := h.shareService.GetShareByToken(token, password)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"title":        share.Title,
		"content":      share.Content,
		"view_count":   share.ViewCount,
		"created_at":   share.CreatedAt,
		"has_password": share.HasPassword,
	})
}
