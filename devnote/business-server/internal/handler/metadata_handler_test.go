package handler

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/devnote/business-server/internal/model"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMetadataCreateSuccess(t *testing.T) {
	r := setupTestRouter(t)

	body := model.NoteMeta{
		Title:   "我的第一篇笔记",
		Author:  "tester",
		Format:  "markdown",
		Excerpt: "摘要内容",
	}
	raw, _ := json.Marshal(body)

	w := doRequest(r, http.MethodPost, "/api/v1/metadata", raw, nil)
	assert.Equal(t, http.StatusCreated, w.Code)

	var resp struct {
		Data model.NoteMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.NotEmpty(t, resp.Data.ID)
	assert.Equal(t, "我的第一篇笔记", resp.Data.Title)
	assert.Equal(t, testAuthUser, resp.Data.UserID)
	assert.False(t, resp.Data.CreatedAt.IsZero())
}

func TestMetadataCreateMissingTitle(t *testing.T) {
	r := setupTestRouter(t)

	body := model.NoteMeta{Author: "tester"}
	raw, _ := json.Marshal(body)

	w := doRequest(r, http.MethodPost, "/api/v1/metadata", raw, nil)
	// service 层返回 title is required，handler 走 respondInternalError → 500
	assert.Equal(t, http.StatusInternalServerError, w.Code)
}

func TestMetadataCreateInvalidJSON(t *testing.T) {
	r := setupTestRouter(t)

	w := doRequest(r, http.MethodPost, "/api/v1/metadata", []byte("{not-json"), nil)
	assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestMetadataUnauthorized(t *testing.T) {
	// 表驱动：所有受保护端点在缺失 user_id 时都应返回 401
	r := setupTestRouter(t)

	tests := []struct {
		name   string
		method string
		target string
	}{
		{"create", http.MethodPost, "/api/v1/metadata"},
		{"get", http.MethodGet, "/api/v1/metadata/some-id"},
		{"update", http.MethodPut, "/api/v1/metadata/some-id"},
		{"delete", http.MethodDelete, "/api/v1/metadata/some-id"},
		{"list", http.MethodGet, "/api/v1/metadata"},
		{"filter", http.MethodGet, "/api/v1/metadata/filter"},
		{"batch", http.MethodPost, "/api/v1/metadata/batch"},
		{"batch-delete", http.MethodPost, "/api/v1/metadata/batch-delete"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := doRequest(r, tt.method, tt.target, nil, map[string]string{"X-Test-No-Auth": "1"})
			assert.Equal(t, http.StatusUnauthorized, w.Code)
		})
	}
}

func TestMetadataGetNotFound(t *testing.T) {
	r := setupTestRouter(t)

	w := doRequest(r, http.MethodGet, "/api/v1/metadata/nonexistent", nil, nil)
	assert.Equal(t, http.StatusNotFound, w.Code)
}

func TestMetadataCRUDFlow(t *testing.T) {
	r := setupTestRouter(t)

	// Create
	createBody := model.NoteMeta{Title: "CRUD 笔记", Author: "flow", Format: "markdown"}
	raw, _ := json.Marshal(createBody)
	w := doRequest(r, http.MethodPost, "/api/v1/metadata", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)

	var createResp struct {
		Data model.NoteMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &createResp))
	noteID := createResp.Data.ID
	require.NotEmpty(t, noteID)

	// Get
	w = doRequest(r, http.MethodGet, "/api/v1/metadata/"+noteID, nil, nil)
	require.Equal(t, http.StatusOK, w.Code)
	var getResp struct {
		Data model.NoteMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &getResp))
	assert.Equal(t, "CRUD 笔记", getResp.Data.Title)

	// Update
	updateBody := model.NoteMeta{Title: "更新后的标题", Author: "flow2"}
	raw, _ = json.Marshal(updateBody)
	w = doRequest(r, http.MethodPut, "/api/v1/metadata/"+noteID, raw, nil)
	require.Equal(t, http.StatusOK, w.Code)
	var updateResp struct {
		Data model.NoteMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &updateResp))
	assert.Equal(t, "更新后的标题", updateResp.Data.Title)

	// Delete
	w = doRequest(r, http.MethodDelete, "/api/v1/metadata/"+noteID, nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	// Get after delete → 404
	w = doRequest(r, http.MethodGet, "/api/v1/metadata/"+noteID, nil, nil)
	assert.Equal(t, http.StatusNotFound, w.Code)
}

func TestMetadataList(t *testing.T) {
	r := setupTestRouter(t)

	// 预置两条数据
	for _, title := range []string{"笔记 A", "笔记 B"} {
		raw, _ := json.Marshal(model.NoteMeta{Title: title})
		w := doRequest(r, http.MethodPost, "/api/v1/metadata", raw, nil)
		require.Equal(t, http.StatusCreated, w.Code)
	}

	w := doRequest(r, http.MethodGet, "/api/v1/metadata?page=1&page_size=10", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp model.PaginatedResponse
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	// Data 是 []interface{}，需断言总数
	assert.Equal(t, 2, resp.Total)
	assert.Equal(t, 1, resp.Page)
	assert.Equal(t, 10, resp.PageSize)
}

func TestMetadataListWithSearch(t *testing.T) {
	r := setupTestRouter(t)

	for _, title := range []string{"Go 语言指南", "Rust 入门", "Python 速查"} {
		raw, _ := json.Marshal(model.NoteMeta{Title: title})
		w := doRequest(r, http.MethodPost, "/api/v1/metadata", raw, nil)
		require.Equal(t, http.StatusCreated, w.Code)
	}

	w := doRequest(r, http.MethodGet, "/api/v1/metadata?search=Go", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp model.PaginatedResponse
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.Equal(t, 1, resp.Total)
}

func TestMetadataFilter(t *testing.T) {
	r := setupTestRouter(t)

	// 预置不同 format 的笔记
	notes := []model.NoteMeta{
		{Title: "md 笔记", Format: "markdown"},
		{Title: "html 笔记", Format: "html"},
		{Title: "md 笔记 2", Format: "markdown"},
	}
	for _, n := range notes {
		raw, _ := json.Marshal(n)
		w := doRequest(r, http.MethodPost, "/api/v1/metadata", raw, nil)
		require.Equal(t, http.StatusCreated, w.Code)
	}

	w := doRequest(r, http.MethodGet, "/api/v1/metadata/filter?format=markdown", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp model.PaginatedResponse
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.Equal(t, 2, resp.Total)
}

func TestMetadataBatchCreate(t *testing.T) {
	r := setupTestRouter(t)

	req := struct {
		Items []*model.NoteMeta `json:"items"`
	}{
		Items: []*model.NoteMeta{
			{Title: "批量 1"},
			{Title: "批量 2"},
			{Title: "批量 3"},
		},
	}
	raw, _ := json.Marshal(req)

	w := doRequest(r, http.MethodPost, "/api/v1/metadata/batch", raw, nil)
	assert.Equal(t, http.StatusCreated, w.Code)

	var resp struct {
		Data []*model.NoteMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.Len(t, resp.Data, 3)
	for _, m := range resp.Data {
		assert.NotEmpty(t, m.ID)
		assert.Equal(t, testAuthUser, m.UserID)
	}
}

func TestMetadataBatchDelete(t *testing.T) {
	r := setupTestRouter(t)

	// 先批量创建
	var ids []string
	for _, title := range []string{"del-1", "del-2"} {
		raw, _ := json.Marshal(model.NoteMeta{Title: title})
		w := doRequest(r, http.MethodPost, "/api/v1/metadata", raw, nil)
		require.Equal(t, http.StatusCreated, w.Code)
		var resp struct {
			Data model.NoteMeta `json:"data"`
		}
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		ids = append(ids, resp.Data.ID)
	}

	// 批量删除
	req := struct {
		IDs []string `json:"ids"`
	}{IDs: ids}
	raw, _ := json.Marshal(req)
	w := doRequest(r, http.MethodPost, "/api/v1/metadata/batch-delete", raw, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	// 验证已删除
	for _, id := range ids {
		w := doRequest(r, http.MethodGet, "/api/v1/metadata/"+id, nil, nil)
		assert.Equal(t, http.StatusNotFound, w.Code)
	}
}
