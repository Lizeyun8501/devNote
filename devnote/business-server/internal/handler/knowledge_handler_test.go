package handler

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/devnote/business-server/internal/model"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// createTestNote 通过 metadata 端点创建一条笔记，返回其 ID。
func createTestNote(t *testing.T, r *gin.Engine) string {
	t.Helper()
	raw, _ := json.Marshal(model.NoteMeta{Title: "知识图谱笔记"})
	w := doRequest(r, http.MethodPost, "/api/v1/metadata", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)
	var resp struct {
		Data model.NoteMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	return resp.Data.ID
}

func TestKnowledgeUnauthorized(t *testing.T) {
	r := setupTestRouter(t)

	tests := []struct {
		name   string
		method string
		target string
	}{
		{"create-relation", http.MethodPost, "/api/v1/knowledge/relations"},
		{"delete-relation", http.MethodDelete, "/api/v1/knowledge/relations/some-id"},
		{"get-relations", http.MethodGet, "/api/v1/knowledge/notes/note-1/relations"},
		{"edges", http.MethodGet, "/api/v1/knowledge/graph/edges"},
		{"metrics", http.MethodGet, "/api/v1/knowledge/graph/metrics"},
		{"orphans", http.MethodGet, "/api/v1/knowledge/graph/orphans"},
		{"coverage", http.MethodGet, "/api/v1/knowledge/graph/coverage"},
		{"suggest", http.MethodGet, "/api/v1/knowledge/suggest/note-1"},
		{"path", http.MethodGet, "/api/v1/knowledge/path"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := doRequest(r, tt.method, tt.target, nil, map[string]string{"X-Test-No-Auth": "1"})
			assert.Equal(t, http.StatusUnauthorized, w.Code)
		})
	}
}

func TestKnowledgeCreateRelationSuccess(t *testing.T) {
	r := setupTestRouter(t)

	noteA := createTestNote(t, r)
	noteB := createTestNote(t, r)

	body := struct {
		SourceNoteID string  `json:"source_note_id"`
		TargetNoteID string  `json:"target_note_id"`
		RelationType string  `json:"relation_type"`
		Weight       float64 `json:"weight"`
	}{
		SourceNoteID: noteA,
		TargetNoteID: noteB,
		RelationType: "link",
		Weight:       0.8,
	}
	raw, _ := json.Marshal(body)

	w := doRequest(r, http.MethodPost, "/api/v1/knowledge/relations", raw, nil)
	assert.Equal(t, http.StatusCreated, w.Code)

	var resp struct {
		Data model.KnowledgeRelation `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.NotEmpty(t, resp.Data.ID)
	assert.Equal(t, noteA, resp.Data.SourceNoteID)
	assert.Equal(t, noteB, resp.Data.TargetNoteID)
	assert.Equal(t, "link", resp.Data.RelationType)
	assert.InDelta(t, 0.8, resp.Data.Weight, 0.001)
}

func TestKnowledgeCreateRelationSelfReference(t *testing.T) {
	r := setupTestRouter(t)

	noteA := createTestNote(t, r)

	body := struct {
		SourceNoteID string `json:"source_note_id"`
		TargetNoteID string `json:"target_note_id"`
	}{
		SourceNoteID: noteA,
		TargetNoteID: noteA,
	}
	raw, _ := json.Marshal(body)

	w := doRequest(r, http.MethodPost, "/api/v1/knowledge/relations", raw, nil)
	assert.Equal(t, http.StatusInternalServerError, w.Code)
}

func TestKnowledgeCreateRelationDefaultValues(t *testing.T) {
	r := setupTestRouter(t)

	noteA := createTestNote(t, r)
	noteB := createTestNote(t, r)

	body := struct {
		SourceNoteID string `json:"source_note_id"`
		TargetNoteID string `json:"target_note_id"`
	}{
		SourceNoteID: noteA,
		TargetNoteID: noteB,
	}
	raw, _ := json.Marshal(body)

	w := doRequest(r, http.MethodPost, "/api/v1/knowledge/relations", raw, nil)
	assert.Equal(t, http.StatusCreated, w.Code)

	var resp struct {
		Data model.KnowledgeRelation `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.Equal(t, "link", resp.Data.RelationType)
	assert.InDelta(t, 1.0, resp.Data.Weight, 0.001)
}

func TestKnowledgeDeleteRelation(t *testing.T) {
	r := setupTestRouter(t)

	noteA := createTestNote(t, r)
	noteB := createTestNote(t, r)

	body := struct {
		SourceNoteID string  `json:"source_note_id"`
		TargetNoteID string  `json:"target_note_id"`
		Weight       float64 `json:"weight"`
	}{SourceNoteID: noteA, TargetNoteID: noteB, Weight: 1.0}
	raw, _ := json.Marshal(body)
	w := doRequest(r, http.MethodPost, "/api/v1/knowledge/relations", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)
	var createResp struct {
		Data model.KnowledgeRelation `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &createResp))

	w = doRequest(r, http.MethodDelete, "/api/v1/knowledge/relations/"+createResp.Data.ID, nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)
}

func TestKnowledgeGetRelations(t *testing.T) {
	r := setupTestRouter(t)

	noteA := createTestNote(t, r)
	noteB := createTestNote(t, r)

	body := struct {
		SourceNoteID string  `json:"source_note_id"`
		TargetNoteID string  `json:"target_note_id"`
		Weight       float64 `json:"weight"`
	}{SourceNoteID: noteA, TargetNoteID: noteB, Weight: 1.0}
	raw, _ := json.Marshal(body)
	w := doRequest(r, http.MethodPost, "/api/v1/knowledge/relations", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)

	w = doRequest(r, http.MethodGet, "/api/v1/knowledge/notes/"+noteA+"/relations", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)
}

func TestKnowledgeGraphComputation(t *testing.T) {
	r := setupTestRouter(t)

	noteA := createTestNote(t, r)
	noteB := createTestNote(t, r)
	noteC := createTestNote(t, r)

	// 创建 A→B、B→C 两条关系
	for _, pair := range [2]struct{ src, tgt string }{
		{noteA, noteB},
		{noteB, noteC},
	} {
		body := struct {
			SourceNoteID string  `json:"source_note_id"`
			TargetNoteID string  `json:"target_note_id"`
			Weight       float64 `json:"weight"`
		}{SourceNoteID: pair.src, TargetNoteID: pair.tgt, Weight: 1.0}
		raw, _ := json.Marshal(body)
		w := doRequest(r, http.MethodPost, "/api/v1/knowledge/relations", raw, nil)
		require.Equal(t, http.StatusCreated, w.Code)
	}

	// edges
	w := doRequest(r, http.MethodGet, "/api/v1/knowledge/graph/edges", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	// metrics
	w = doRequest(r, http.MethodGet, "/api/v1/knowledge/graph/metrics", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	// orphans
	w = doRequest(r, http.MethodGet, "/api/v1/knowledge/graph/orphans", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	// coverage
	w = doRequest(r, http.MethodGet, "/api/v1/knowledge/graph/coverage", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)
}

func TestKnowledgeSuggestRelated(t *testing.T) {
	r := setupTestRouter(t)

	noteA := createTestNote(t, r)
	noteB := createTestNote(t, r)

	body := struct {
		SourceNoteID string  `json:"source_note_id"`
		TargetNoteID string  `json:"target_note_id"`
		Weight       float64 `json:"weight"`
	}{SourceNoteID: noteA, TargetNoteID: noteB, Weight: 1.0}
	raw, _ := json.Marshal(body)
	w := doRequest(r, http.MethodPost, "/api/v1/knowledge/relations", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)

	w = doRequest(r, http.MethodGet, "/api/v1/knowledge/suggest/"+noteA+"?limit=5", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)
}

func TestKnowledgeFindShortestPath(t *testing.T) {
	r := setupTestRouter(t)

	noteA := createTestNote(t, r)
	noteB := createTestNote(t, r)
	noteC := createTestNote(t, r)

	// A → B → C
	for _, pair := range [2]struct{ src, tgt string }{
		{noteA, noteB},
		{noteB, noteC},
	} {
		body := struct {
			SourceNoteID string  `json:"source_note_id"`
			TargetNoteID string  `json:"target_note_id"`
			Weight       float64 `json:"weight"`
		}{SourceNoteID: pair.src, TargetNoteID: pair.tgt, Weight: 1.0}
		raw, _ := json.Marshal(body)
		w := doRequest(r, http.MethodPost, "/api/v1/knowledge/relations", raw, nil)
		require.Equal(t, http.StatusCreated, w.Code)
	}

	w := doRequest(r, http.MethodGet, "/api/v1/knowledge/path?from="+noteA+"&to="+noteC, nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp struct {
		Data struct {
			Path     []string `json:"path"`
			Distance float64  `json:"distance"`
		} `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.NotEmpty(t, resp.Data.Path)
}

func TestKnowledgeFindShortestPathMissingParams(t *testing.T) {
	r := setupTestRouter(t)

	w := doRequest(r, http.MethodGet, "/api/v1/knowledge/path", nil, nil)
	assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestKnowledgeFindShortestPathNoPath(t *testing.T) {
	r := setupTestRouter(t)

	noteA := createTestNote(t, r)
	noteB := createTestNote(t, r)

	// 不创建关系，查找路径应返回 404
	w := doRequest(r, http.MethodGet, "/api/v1/knowledge/path?from="+noteA+"&to="+noteB, nil, nil)
	assert.Equal(t, http.StatusNotFound, w.Code)
}
