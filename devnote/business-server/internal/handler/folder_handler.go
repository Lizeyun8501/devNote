package handler

import (
	"net/http"
	"strconv"

	"github.com/devnote/business-server/internal/model"
	"github.com/devnote/business-server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// FolderHandler handles HTTP requests for directory/folder management.
type FolderHandler struct {
	svc    *service.FolderService
	logger *zap.Logger
}

// NewFolderHandler creates a new FolderHandler.
func NewFolderHandler(svc *service.FolderService, logger *zap.Logger) *FolderHandler {
	return &FolderHandler{svc: svc, logger: logger}
}

// Create handles POST /api/v1/folders
func (h *FolderHandler) Create(c *gin.Context) {
	var req model.FolderMeta
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}
	result, err := h.svc.Create(&req)
	if err != nil {
		h.logger.Error("create folder failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusCreated, model.SuccessResponse{Data: result})
}

// Get handles GET /api/v1/folders/:id
func (h *FolderHandler) Get(c *gin.Context) {
	id := c.Param("id")
	result, err := h.svc.Get(id)
	if err != nil {
		h.logger.Error("get folder failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusNotFound, model.ErrorResponse{Code: 404, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: result})
}

// Update handles PUT /api/v1/folders/:id
func (h *FolderHandler) Update(c *gin.Context) {
	id := c.Param("id")
	var req model.FolderMeta
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}
	req.ID = id
	result, err := h.svc.Update(&req)
	if err != nil {
		h.logger.Error("update folder failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: result})
}

// Delete handles DELETE /api/v1/folders/:id
func (h *FolderHandler) Delete(c *gin.Context) {
	id := c.Param("id")
	cascade, _ := strconv.ParseBool(c.DefaultQuery("cascade", "false"))
	if err := h.svc.Delete(id, cascade); err != nil {
		h.logger.Error("delete folder failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: gin.H{"deleted": id}})
}

// List handles GET /api/v1/folders
func (h *FolderHandler) List(c *gin.Context) {
	parentID := c.DefaultQuery("parent_id", "")
	result, err := h.svc.List(parentID)
	if err != nil {
		h.logger.Error("list folders failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: result})
}

// GetTree handles GET /api/v1/folders/tree
func (h *FolderHandler) GetTree(c *gin.Context) {
	parentID := c.DefaultQuery("parent_id", "")
	tree, err := h.svc.GetTree(parentID)
	if err != nil {
		h.logger.Error("get folder tree failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: tree})
}

// ----------------------------------------------------------------
// Move / Copy
// ----------------------------------------------------------------

// MoveFolder handles POST /api/v1/folders/:id/move
func (h *FolderHandler) MoveFolder(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		NewParentID string `json:"new_parent_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}
	if err := h.svc.MoveFolder(id, req.NewParentID); err != nil {
		h.logger.Error("move folder failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: gin.H{"moved": true}})
}

// CopyFolder handles POST /api/v1/folders/:id/copy
func (h *FolderHandler) CopyFolder(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		NewParentID string `json:"new_parent_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}
	result, err := h.svc.CopyFolder(id, req.NewParentID)
	if err != nil {
		h.logger.Error("copy folder failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: result})
}

// ----------------------------------------------------------------
// Path resolution
// ----------------------------------------------------------------

// ResolvePath handles GET /api/v1/folders/:id/path
func (h *FolderHandler) ResolvePath(c *gin.Context) {
	id := c.Param("id")
	path, err := h.svc.ResolvePath(id)
	if err != nil {
		h.logger.Error("resolve path failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: gin.H{"path": path}})
}

// ----------------------------------------------------------------
// Folder-note associations
// ----------------------------------------------------------------

// GetNotesByFolder handles GET /api/v1/folders/:id/notes
func (h *FolderHandler) GetNotesByFolder(c *gin.Context) {
	id := c.Param("id")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	result, err := h.svc.GetNotesByFolder(id, page, pageSize)
	if err != nil {
		h.logger.Error("get notes by folder failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, result)
}