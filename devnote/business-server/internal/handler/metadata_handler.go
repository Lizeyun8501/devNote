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
	var req model.NoteMeta
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}

	result, err := h.svc.Create(&req)
	if err != nil {
		h.logger.Error("create metadata failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}

	c.JSON(http.StatusCreated, model.SuccessResponse{Data: result})
}

// Get handles GET /api/v1/metadata/:id
func (h *MetadataHandler) Get(c *gin.Context) {
	id := c.Param("id")
	result, err := h.svc.Get(id)
	if err != nil {
		h.logger.Error("get metadata failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusNotFound, model.ErrorResponse{Code: 404, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: result})
}

// Update handles PUT /api/v1/metadata/:id
func (h *MetadataHandler) Update(c *gin.Context) {
	id := c.Param("id")
	var req model.NoteMeta
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}
	req.ID = id

	result, err := h.svc.Update(&req)
	if err != nil {
		h.logger.Error("update metadata failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: result})
}

// Delete handles DELETE /api/v1/metadata/:id
func (h *MetadataHandler) Delete(c *gin.Context) {
	id := c.Param("id")
	if err := h.svc.Delete(id); err != nil {
		h.logger.Error("delete metadata failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: gin.H{"deleted": id}})
}

// List handles GET /api/v1/metadata
func (h *MetadataHandler) List(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	search := c.Query("search")

	result, err := h.svc.List(page, pageSize, search)
	if err != nil {
		h.logger.Error("list metadata failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, result)
}

// Filter handles GET /api/v1/metadata/filter
func (h *MetadataHandler) Filter(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	filterMap := map[string]string{
		"format":   c.Query("format"),
		"author":   c.Query("author"),
		"language": c.Query("language"),
	}

	result, err := h.svc.Filter(filterMap, page, pageSize)
	if err != nil {
		h.logger.Error("filter metadata failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, result)
}

// BatchCreate handles POST /api/v1/metadata/batch
func (h *MetadataHandler) BatchCreate(c *gin.Context) {
	var req struct {
		Items []*model.NoteMeta `json:"items"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}

	result, err := h.svc.BatchCreate(req.Items)
	if err != nil {
		h.logger.Error("batch create metadata failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusCreated, model.SuccessResponse{Data: result})
}

// BatchDelete handles POST /api/v1/metadata/batch-delete
func (h *MetadataHandler) BatchDelete(c *gin.Context) {
	var req struct {
		IDs []string `json:"ids"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}

	if err := h.svc.BatchDelete(req.IDs); err != nil {
		h.logger.Error("batch delete metadata failed", zap.Error(err))
		c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: gin.H{"deleted": len(req.IDs)}})
}