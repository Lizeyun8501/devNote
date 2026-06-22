package handler

import (
	"net/http"
	"strconv"
	"time"

	"github.com/devnote/sync-server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type SyncHandler struct {
	syncService *service.SyncService
	logger      *zap.Logger
}

func NewSyncHandler(syncService *service.SyncService, logger *zap.Logger) *SyncHandler {
	if logger == nil {
		logger = zap.NewNop()
	}
	return &SyncHandler{syncService: syncService, logger: logger}
}

func (h *SyncHandler) Push(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user_id not found in context"})
		return
	}

	var req service.PushRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	resp, err := h.syncService.Push(userID, &req)
	if err != nil {
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}

	c.JSON(http.StatusOK, resp)
}

func (h *SyncHandler) Pull(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user_id not found in context"})
		return
	}

	var req service.PullRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	limitStr := c.Query("limit")
	limit := 100 // Default page size
	if limitStr != "" {
		parsed, err := strconv.Atoi(limitStr)
		if err != nil || parsed <= 0 || parsed > 1000 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid limit"})
			return
		}
		limit = parsed
	}

	resp, err := h.syncService.Pull(userID, &req, limit)
	if err != nil {
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}

	c.JSON(http.StatusOK, resp)
}

func (h *SyncHandler) Status(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user_id not found in context"})
		return
	}
	deviceID := c.Query("device_id")
	if deviceID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "device_id required"})
		return
	}

	status, err := h.syncService.GetStatus(userID, deviceID)
	if err != nil {
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}

	c.JSON(http.StatusOK, status)
}

func (h *SyncHandler) ResolveConflict(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user_id not found in context"})
		return
	}

	var resolution service.ConflictResolution
	if err := c.ShouldBindJSON(&resolution); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.syncService.ResolveConflict(userID, &resolution); err != nil {
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "resolved"})
}

// GetNoteHistory 获取笔记版本历史
func (h *SyncHandler) GetNoteHistory(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user_id not found in context"})
		return
	}
	noteID := c.Param("noteId")

	limitStr := c.DefaultQuery("limit", "50")
	limit, err := strconv.Atoi(limitStr)
	if err != nil || limit <= 0 || limit > 1000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid limit"})
		return
	}

	snapshots, err := h.syncService.GetNoteHistory(userID, noteID, limit)
	if err != nil {
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}

	// 转换为响应格式
	type VersionItem struct {
		Version   int64     `json:"version"`
		Content   string    `json:"content"`
		Checksum  string    `json:"checksum"`
		CreatedAt time.Time `json:"created_at"`
	}

	items := make([]VersionItem, len(snapshots))
	for i, s := range snapshots {
		items[i] = VersionItem{
			Version:   s.Version,
			Content:   s.Content,
			Checksum:  s.Checksum,
			CreatedAt: s.CreatedAt,
		}
	}

	c.JSON(http.StatusOK, gin.H{"versions": items})
}

// GetNoteVersion 获取笔记特定版本
func (h *SyncHandler) GetNoteVersion(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user_id not found in context"})
		return
	}
	noteID := c.Param("noteId")
	versionStr := c.Param("version")
	version, err := strconv.ParseInt(versionStr, 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid version"})
		return
	}

	snapshot, err := h.syncService.GetNoteVersion(userID, noteID, version)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "version not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"version":    snapshot.Version,
		"content":    snapshot.Content,
		"checksum":   snapshot.Checksum,
		"created_at": snapshot.CreatedAt,
	})
}
