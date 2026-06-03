package handler

import (
	"net/http"

	"github.com/devnote/business-server/internal/model"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// HealthHandler provides a simple health-check endpoint.
type HealthHandler struct {
	logger *zap.Logger
}

// NewHealthHandler creates a new HealthHandler.
func NewHealthHandler(logger *zap.Logger) *HealthHandler {
	return &HealthHandler{logger: logger}
}

// Check handles GET /api/v1/health
func (h *HealthHandler) Check(c *gin.Context) {
	h.logger.Debug("health check called")
	c.JSON(http.StatusOK, model.SuccessResponse{Data: gin.H{
		"status":  "ok",
		"service": "business-server",
	}})
}