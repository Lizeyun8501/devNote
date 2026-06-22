package handler

import (
	"net/http"
	"strconv"

	"github.com/devnote/business-server/internal/model"
	"github.com/devnote/business-server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// MetadataHandler handles HTTP requests for note metadata.
type MetadataHandler struct {
	svc    *service.MetadataService
	logger *zap.Logger
}

// NewMetadataHandler creates a new MetadataHandler.
func NewMetadataHandler(svc *service.MetadataService, logger *zap.Logger) *MetadataHandler {
	return &MetadataHandler{svc: svc, logger: logger}
}

// Create handles POST /api/v1/metadata
func (h *MetadataHandler) Create(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}

	var req model.NoteMeta
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}

	result, err := h.svc.Create(userID, &req)
	if err != nil {
		h.logger.Error("create metadata failed", zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}

	c.JSON(http.StatusCreated, model.SuccessResponse{Data: result})
}

// Get handles GET /api/v1/metadata/:id
func (h *MetadataHandler) Get(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}

	id := c.Param("id")
	result, err := h.svc.Get(userID, id)
	if err != nil {
		h.logger.Error("get metadata failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusNotFound, model.ErrorResponse{Code: 404, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: result})
}

// Update handles PUT /api/v1/metadata/:id
func (h *MetadataHandler) Update(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}

	id := c.Param("id")
	var req model.NoteMeta
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}
	req.ID = id

	result, err := h.svc.Update(userID, &req)
	if err != nil {
		h.logger.Error("update metadata failed", zap.String("id", id), zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: result})
}

// Delete handles DELETE /api/v1/metadata/:id
func (h *MetadataHandler) Delete(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}

	id := c.Param("id")
	if err := h.svc.Delete(userID, id); err != nil {
		h.logger.Error("delete metadata failed", zap.String("id", id), zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: gin.H{"deleted": id}})
}

// List handles GET /api/v1/metadata
func (h *MetadataHandler) List(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	search := c.Query("search")

	result, err := h.svc.List(userID, page, pageSize, search)
	if err != nil {
		h.logger.Error("list metadata failed", zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, result)
}

// Filter handles GET /api/v1/metadata/filter
func (h *MetadataHandler) Filter(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	filterMap := map[string]string{
		"format":   c.Query("format"),
		"author":   c.Query("author"),
		"language": c.Query("language"),
	}

	result, err := h.svc.Filter(userID, filterMap, page, pageSize)
	if err != nil {
		h.logger.Error("filter metadata failed", zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, result)
}

// BatchCreate handles POST /api/v1/metadata/batch
func (h *MetadataHandler) BatchCreate(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}

	var req struct {
		Items []*model.NoteMeta `json:"items"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}

	result, err := h.svc.BatchCreate(userID, req.Items)
	if err != nil {
		h.logger.Error("batch create metadata failed", zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusCreated, model.SuccessResponse{Data: result})
}

// BatchDelete handles POST /api/v1/metadata/batch-delete
func (h *MetadataHandler) BatchDelete(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}

	var req struct {
		IDs []string `json:"ids"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}

	if err := h.svc.BatchDelete(userID, req.IDs); err != nil {
		h.logger.Error("batch delete metadata failed", zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: gin.H{"deleted": len(req.IDs)}})
}
