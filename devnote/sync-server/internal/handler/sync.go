package handler

import (
	"net/http"
	"strconv"
	"time"

	"github.com/devnote/sync-server/internal/service"
	"github.com/gin-gonic/gin"
)

type SyncHandler struct {
	syncService *service.SyncService
}

func NewSyncHandler(syncService *service.SyncService) *SyncHandler {
	return &SyncHandler{syncService: syncService}
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
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
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

	limit, _ := strconv.Atoi(c.Query("limit"))
	if limit <= 0 || limit > 1000 {
		limit = 100 // Default page size
	}

	resp, err := h.syncService.Pull(userID, &req, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
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
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
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
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
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
	limit, _ := strconv.Atoi(limitStr)

	snapshots, err := h.syncService.GetNoteHistory(userID, noteID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
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
	version, _ := strconv.ParseInt(versionStr, 10, 64)

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
