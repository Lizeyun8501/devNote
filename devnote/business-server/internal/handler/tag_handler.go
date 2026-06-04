package handler

import (
	"net/http"
	"strconv"

	"github.com/devnote/business-server/internal/model"
	"github.com/devnote/business-server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// TagHandler handles HTTP requests for tag management.
type TagHandler struct {
	svc    *service.TagService
	logger *zap.Logger
}

// NewTagHandler creates a new TagHandler.
func NewTagHandler(svc *service.TagService, logger *zap.Logger) *TagHandler {
	return &TagHandler{svc: svc, logger: logger}
}

// Create handles POST /api/v1/tags
func (h *TagHandler) Create(c *gin.Context) {
	var req model.TagMeta
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}
	result, err := h.svc.Create(&req)
	if err != nil {
		h.logger.Error("create tag failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusCreated, model.SuccessResponse{Data: result})
}

// Get handles GET /api/v1/tags/:id
func (h *TagHandler) Get(c *gin.Context) {
	id := c.Param("id")
	result, err := h.svc.Get(id)
	if err != nil {
		h.logger.Error("get tag failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusNotFound, model.ErrorResponse{Code: 404, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: result})
}

// Update handles PUT /api/v1/tags/:id
func (h *TagHandler) Update(c *gin.Context) {
	id := c.Param("id")
	var req model.TagMeta
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}
	req.ID = id
	result, err := h.svc.Update(&req)
	if err != nil {
		h.logger.Error("update tag failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: result})
}

// Delete handles DELETE /api/v1/tags/:id
func (h *TagHandler) Delete(c *gin.Context) {
	id := c.Param("id")
	if err := h.svc.Delete(id); err != nil {
		h.logger.Error("delete tag failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: gin.H{"deleted": id}})
}

// List handles GET /api/v1/tags
func (h *TagHandler) List(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	search := c.Query("search")

	result, err := h.svc.List(page, pageSize, search)
	if err != nil {
		h.logger.Error("list tags failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, result)
}

// GetChildren handles GET /api/v1/tags/:id/children
func (h *TagHandler) GetChildren(c *gin.Context) {
	id := c.Param("id")
	children, err := h.svc.GetChildren(id)
	if err != nil {
		h.logger.Error("get tag children failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: children})
}

// GetHierarchy handles GET /api/v1/tags/:id/hierarchy
func (h *TagHandler) GetHierarchy(c *gin.Context) {
	id := c.Param("id")
	hierarchy, err := h.svc.GetHierarchy(id)
	if err != nil {
		h.logger.Error("get tag hierarchy failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: hierarchy})
}

// ----------------------------------------------------------------
// Tag-note associations
// ----------------------------------------------------------------

// LinkTag handles POST /api/v1/tags/:id/notes/:noteId
func (h *TagHandler) LinkTag(c *gin.Context) {
	tagID := c.Param("id")
	noteID := c.Param("noteId")
	result, err := h.svc.LinkTagToNote(tagID, noteID)
	if err != nil {
		h.logger.Error("link tag to note failed", zap.String("tag_id", tagID), zap.String("note_id", noteID), zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: result})
}

// UnlinkTag handles DELETE /api/v1/tags/:id/notes/:noteId
func (h *TagHandler) UnlinkTag(c *gin.Context) {
	tagID := c.Param("id")
	noteID := c.Param("noteId")
	if err := h.svc.UnlinkTagFromNote(tagID, noteID); err != nil {
		h.logger.Error("unlink tag failed", zap.String("tag_id", tagID), zap.String("note_id", noteID), zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: gin.H{"unlinked": true}})
}

// GetNotesByTag handles GET /api/v1/tags/:id/notes
func (h *TagHandler) GetNotesByTag(c *gin.Context) {
	tagID := c.Param("id")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	result, err := h.svc.GetNotesByTag(tagID, page, pageSize)
	if err != nil {
		h.logger.Error("get notes by tag failed", zap.String("tag_id", tagID), zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, result)
}

// GetTagsByNote handles GET /api/v1/tags/by-note/:noteId
func (h *TagHandler) GetTagsByNote(c *gin.Context) {
	noteID := c.Param("noteId")
	tags, err := h.svc.GetTagsByNote(noteID)
	if err != nil {
		h.logger.Error("get tags by note failed", zap.String("note_id", noteID), zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: tags})
}

// ----------------------------------------------------------------
// Merge / Split
// ----------------------------------------------------------------

// MergeTags handles POST /api/v1/tags/merge
func (h *TagHandler) MergeTags(c *gin.Context) {
	var req struct {
		SourceTagID string `json:"source_tag_id"`
		TargetTagID string `json:"target_tag_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}
	if err := h.svc.MergeTags(req.SourceTagID, req.TargetTagID); err != nil {
		h.logger.Error("merge tags failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: gin.H{"merged": true}})
}

// SplitTag handles POST /api/v1/tags/split
func (h *TagHandler) SplitTag(c *gin.Context) {
	var req struct {
		SourceTagID string   `json:"source_tag_id"`
		NewTagName  string   `json:"new_tag_name"`
		NoteIDs     []string `json:"note_ids"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}
	result, err := h.svc.SplitTag(req.SourceTagID, req.NewTagName, req.NoteIDs)
	if err != nil {
		h.logger.Error("split tag failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: result})
}

// ----------------------------------------------------------------
// Statistics
// ----------------------------------------------------------------

// GetStats handles GET /api/v1/tags/:id/stats
func (h *TagHandler) GetStats(c *gin.Context) {
	id := c.Param("id")
	stats, err := h.svc.GetStats(id)
	if err != nil {
		h.logger.Error("get tag stats failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: stats})
}

// GetTopTags handles GET /api/v1/tags/top
func (h *TagHandler) GetTopTags(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "10"))
	tags, err := h.svc.GetTopTags(limit)
	if err != nil {
		h.logger.Error("get top tags failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: tags})
}