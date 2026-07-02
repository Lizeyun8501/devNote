package handler

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/devnote/sync-server/internal/service"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"go.uber.org/zap"
)

// ClipperHandler 处理网页剪藏扩展发起的剪藏请求。
type ClipperHandler struct {
	syncService *service.SyncService
	logger      *zap.Logger
}

func NewClipperHandler(syncService *service.SyncService, logger *zap.Logger) *ClipperHandler {
	if logger == nil {
		logger = zap.NewNop()
	}
	return &ClipperHandler{syncService: syncService, logger: logger}
}

// ClipRequest 剪藏请求
type ClipRequest struct {
	Title     string   `json:"title" binding:"required"`
	Content   string   `json:"content" binding:"required"` // Markdown 格式
	SourceURL string   `json:"source_url" binding:"required"`
	FolderID  string   `json:"folder_id"`
	Tags      []string `json:"tags"`
}

// ClipResponse 剪藏响应
type ClipResponse struct {
	NoteID    string    `json:"note_id"`
	Version   int64     `json:"version"`
	CreatedAt time.Time `json:"created_at"`
}

// Clip 处理网页剪藏：将剪藏内容作为一条新笔记通过 SyncService.Push 持久化。
func (h *ClipperHandler) Clip(c *gin.Context) {
	userID := c.GetString("user_id") // 从 JWT 中间件获取
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user_id not found in context"})
		return
	}

	var req ClipRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request: " + err.Error()})
		return
	}

	// 生成笔记 ID
	noteID := uuid.New().String()

	// 构造笔记内容（JSON 格式，包含 source_url 等元数据）
	noteContent := map[string]interface{}{
		"title":      req.Title,
		"content":    req.Content,
		"source_url": req.SourceURL,
		"clipped_at": time.Now().UTC().Format(time.RFC3339),
		"tags":       req.Tags,
	}
	if req.FolderID != "" {
		noteContent["folder_id"] = req.FolderID
	}
	contentJSON, err := json.Marshal(noteContent)
	if err != nil {
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}

	// 通过 SyncService.Push 创建笔记
	// P1 修复 (G5): 原实现所有 web-clipper 用户共用 DeviceID="web-clipper"，
	// 导致 SyncService.Push 中按 (user_id, device_id) 维度的设备同步状态相互覆盖。
	// 现改为按用户隔离，确保每个 web-clipper 用户拥有独立的设备同步游标。
	pushReq := &service.PushRequest{
		DeviceID: "web-clipper-" + userID,
		Records: []service.SyncRecordInput{
			{
				NoteID:  noteID,
				Action:  "create",
				Version: 0,
				Payload: string(contentJSON),
			},
		},
	}

	// 修复: Push 在 P1 分页改造后新增 limit 参数（默认 100，最大 1000），
	// 剪藏仅推送单条记录，传默认 100 不会截断。
	if _, err := h.syncService.Push(userID, pushReq, 100); err != nil {
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}

	// PushResponse 不返回每条 record 的版本号，因此查询实际分配到的版本。
	version, err := h.syncService.GetNoteLatestVersion(userID, noteID)
	if err != nil {
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}

	c.JSON(http.StatusOK, ClipResponse{
		NoteID:    noteID,
		Version:   version,
		CreatedAt: time.Now().UTC(),
	})
}
