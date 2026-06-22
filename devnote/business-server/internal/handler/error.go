package handler

import (
	"net/http"

	"github.com/devnote/business-server/internal/model"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// respondInternalError logs the actual error but returns a generic message to the client.
func respondInternalError(c *gin.Context, logger *zap.Logger, publicMsg string, err error) {
	if err != nil {
		logger.Error(publicMsg, zap.Error(err))
	}
	c.JSON(http.StatusInternalServerError, model.ErrorResponse{Code: 500, Message: publicMsg})
}
