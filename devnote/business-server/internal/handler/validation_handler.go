package handler

import (
	"net/http"

	"github.com/devnote/business-server/internal/model"
	"github.com/devnote/business-server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// ValidationHandler handles HTTP requests for rule validation.
type ValidationHandler struct {
	svc    service.ValidationServiceInterface
	logger *zap.Logger
}

// NewValidationHandler creates a new ValidationHandler.
func NewValidationHandler(svc service.ValidationServiceInterface, logger *zap.Logger) *ValidationHandler {
	return &ValidationHandler{svc: svc, logger: logger}
}

// ValidateNote handles GET /api/v1/validate/note/:id
func (h *ValidationHandler) ValidateNote(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	id := c.Param("id")
	report, err := h.svc.ValidateNote(userID, id)
	if err != nil {
		h.logger.Error("validate note failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusNotFound, model.ErrorResponse{Code: 404, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: report})
}

// ValidateFolder handles GET /api/v1/validate/folder/:id
func (h *ValidationHandler) ValidateFolder(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	id := c.Param("id")
	report, err := h.svc.ValidateFolder(userID, id)
	if err != nil {
		h.logger.Error("validate folder failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusNotFound, model.ErrorResponse{Code: 404, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: report})
}

// ValidateTag handles GET /api/v1/validate/tag/:id
func (h *ValidationHandler) ValidateTag(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	id := c.Param("id")
	report, err := h.svc.ValidateTag(userID, id)
	if err != nil {
		h.logger.Error("validate tag failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusNotFound, model.ErrorResponse{Code: 404, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: report})
}

// ValidateKnowledgeRelation handles GET /api/v1/validate/knowledge/:id
func (h *ValidationHandler) ValidateKnowledgeRelation(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	id := c.Param("id")
	report, err := h.svc.ValidateKnowledgeRelation(userID, id)
	if err != nil {
		h.logger.Error("validate knowledge relation failed", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusNotFound, model.ErrorResponse{Code: 404, Message: err.Error()})
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: report})
}

// ----------------------------------------------------------------
// Validation rule CRUD
// ----------------------------------------------------------------

// CreateRule handles POST /api/v1/validate/rules
func (h *ValidationHandler) CreateRule(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	var req model.ValidationRule
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}
	result, err := h.svc.CreateRule(userID, &req)
	if err != nil {
		h.logger.Error("create validation rule failed", zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusCreated, model.SuccessResponse{Data: result})
}

// ListRules handles GET /api/v1/validate/rules
func (h *ValidationHandler) ListRules(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	rules, err := h.svc.ListRules(userID)
	if err != nil {
		h.logger.Error("list validation rules failed", zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: rules})
}

// UpdateRule handles PUT /api/v1/validate/rules/:id
func (h *ValidationHandler) UpdateRule(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	id := c.Param("id")
	var req model.ValidationRule
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}
	req.ID = id
	result, err := h.svc.UpdateRule(userID, &req)
	if err != nil {
		h.logger.Error("update validation rule failed", zap.String("id", id), zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: result})
}

// DeleteRule handles DELETE /api/v1/validate/rules/:id
func (h *ValidationHandler) DeleteRule(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	id := c.Param("id")
	if err := h.svc.DeleteRule(userID, id); err != nil {
		h.logger.Error("delete validation rule failed", zap.String("id", id), zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: gin.H{"deleted": id}})
}

// ----------------------------------------------------------------
// Business rule CRUD
// ----------------------------------------------------------------

// CreateBusinessRule handles POST /api/v1/validate/business-rules
func (h *ValidationHandler) CreateBusinessRule(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	var req model.BusinessRule
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}
	result, err := h.svc.CreateBusinessRule(userID, &req)
	if err != nil {
		h.logger.Error("create business rule failed", zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusCreated, model.SuccessResponse{Data: result})
}

// ListBusinessRules handles GET /api/v1/validate/business-rules
func (h *ValidationHandler) ListBusinessRules(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	rules, err := h.svc.ListBusinessRules(userID)
	if err != nil {
		h.logger.Error("list business rules failed", zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: rules})
}

// UpdateBusinessRule handles PUT /api/v1/validate/business-rules/:id
func (h *ValidationHandler) UpdateBusinessRule(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	id := c.Param("id")
	var req model.BusinessRule
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}
	req.ID = id
	result, err := h.svc.UpdateBusinessRule(userID, &req)
	if err != nil {
		h.logger.Error("update business rule failed", zap.String("id", id), zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: result})
}

// DeleteBusinessRule handles DELETE /api/v1/validate/business-rules/:id
func (h *ValidationHandler) DeleteBusinessRule(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	id := c.Param("id")
	if err := h.svc.DeleteBusinessRule(userID, id); err != nil {
		h.logger.Error("delete business rule failed", zap.String("id", id), zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: gin.H{"deleted": id}})
}
