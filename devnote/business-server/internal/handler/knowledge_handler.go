package handler

import (
	"net/http"
	"strconv"

	"github.com/devnote/business-server/internal/model"
	"github.com/devnote/business-server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// KnowledgeHandler handles HTTP requests for knowledge relationship computation.
type KnowledgeHandler struct {
	svc    *service.KnowledgeService
	logger *zap.Logger
}

// NewKnowledgeHandler creates a new KnowledgeHandler.
func NewKnowledgeHandler(svc *service.KnowledgeService, logger *zap.Logger) *KnowledgeHandler {
	return &KnowledgeHandler{svc: svc, logger: logger}
}

// CreateRelation handles POST /api/v1/knowledge/relations
func (h *KnowledgeHandler) CreateRelation(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	var req struct {
		SourceNoteID string  `json:"source_note_id"`
		TargetNoteID string  `json:"target_note_id"`
		RelationType string  `json:"relation_type"`
		Weight       float64 `json:"weight"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "invalid request body", Detail: err.Error()})
		return
	}
	if req.RelationType == "" {
		req.RelationType = "link"
	}
	if req.Weight <= 0 {
		req.Weight = 1.0
	}

	result, err := h.svc.CreateRelation(userID, req.SourceNoteID, req.TargetNoteID, req.RelationType, req.Weight)
	if err != nil {
		h.logger.Error("create knowledge relation failed", zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusCreated, model.SuccessResponse{Data: result})
}

// DeleteRelation handles DELETE /api/v1/knowledge/relations/:id
func (h *KnowledgeHandler) DeleteRelation(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	id := c.Param("id")
	if err := h.svc.DeleteRelation(userID, id); err != nil {
		h.logger.Error("delete knowledge relation failed", zap.String("id", id), zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: gin.H{"deleted": id}})
}

// GetRelations handles GET /api/v1/knowledge/notes/:noteId/relations
func (h *KnowledgeHandler) GetRelations(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	noteID := c.Param("noteId")
	relations, err := h.svc.GetRelations(userID, noteID)
	if err != nil {
		h.logger.Error("get relations failed", zap.String("note_id", noteID), zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: relations})
}

// ----------------------------------------------------------------
// Graph computation
// ----------------------------------------------------------------

// ComputeEdges handles GET /api/v1/knowledge/graph/edges
func (h *KnowledgeHandler) ComputeEdges(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	edges, err := h.svc.ComputeGraphEdges(userID)
	if err != nil {
		h.logger.Error("compute graph edges failed", zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: edges})
}

// ComputeMetrics handles GET /api/v1/knowledge/graph/metrics
func (h *KnowledgeHandler) ComputeMetrics(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	metrics, err := h.svc.ComputeMetrics(userID)
	if err != nil {
		h.logger.Error("compute graph metrics failed", zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: metrics})
}

// FindOrphans handles GET /api/v1/knowledge/graph/orphans
func (h *KnowledgeHandler) FindOrphans(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	// 修复(P0): 传播 FindOrphanNotes 的错误，而非忽略。
	orphans, err := h.svc.FindOrphanNotes(userID)
	if err != nil {
		h.logger.Error("find orphan notes failed", zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: orphans})
}

// ComputeCoverage handles GET /api/v1/knowledge/graph/coverage
func (h *KnowledgeHandler) ComputeCoverage(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	cov, err := h.svc.ComputeCoverage(userID)
	if err != nil {
		h.logger.Error("compute coverage failed", zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: cov})
}

// ----------------------------------------------------------------
// Suggestions & pathfinding
// ----------------------------------------------------------------

// SuggestRelated handles GET /api/v1/knowledge/suggest/:noteId
func (h *KnowledgeHandler) SuggestRelated(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	noteID := c.Param("noteId")
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "10"))

	suggestions, err := h.svc.SuggestRelatedNotes(userID, noteID, limit)
	if err != nil {
		h.logger.Error("suggest related failed", zap.String("note_id", noteID), zap.Error(err))
		respondInternalError(c, h.logger, "internal server error", err)
		return
	}
	c.JSON(http.StatusOK, model.SuccessResponse{Data: suggestions})
}

// FindShortestPath handles GET /api/v1/knowledge/path
func (h *KnowledgeHandler) FindShortestPath(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, model.ErrorResponse{Code: 401, Message: "missing user identity"})
		return
	}
	from := c.Query("from")
	to := c.Query("to")
	if from == "" || to == "" {
		c.JSON(http.StatusBadRequest, model.ErrorResponse{Code: 400, Message: "both 'from' and 'to' query parameters are required"})
		return
	}

	path, distance, err := h.svc.FindShortestPath(userID, from, to)
	if err != nil {
		h.logger.Error("find shortest path failed", zap.String("from", from), zap.String("to", to), zap.Error(err))
		c.JSON(http.StatusNotFound, model.ErrorResponse{Code: 404, Message: err.Error()})
		return
	}

	c.JSON(http.StatusOK, model.SuccessResponse{Data: gin.H{
		"path":     path,
		"distance": distance,
	}})
}
