package handler

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/devnote/business-server/internal/model"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTagCreateSuccess(t *testing.T) {
	r := setupTestRouter(t)

	body := model.TagMeta{Name: "重要", Color: "#ff0000", Description: "高优先级标签"}
	raw, _ := json.Marshal(body)

	w := doRequest(r, http.MethodPost, "/api/v1/tags", raw, nil)
	assert.Equal(t, http.StatusCreated, w.Code)

	var resp struct {
		Data model.TagMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.NotEmpty(t, resp.Data.ID)
	assert.Equal(t, "重要", resp.Data.Name)
	assert.Equal(t, testAuthUser, resp.Data.UserID)
}

func TestTagCreateMissingName(t *testing.T) {
	r := setupTestRouter(t)

	body := model.TagMeta{Color: "#000"}
	raw, _ := json.Marshal(body)

	w := doRequest(r, http.MethodPost, "/api/v1/tags", raw, nil)
	assert.Equal(t, http.StatusInternalServerError, w.Code)
}

func TestTagUnauthorized(t *testing.T) {
	r := setupTestRouter(t)

	tests := []struct {
		name   string
		method string
		target string
	}{
		{"create", http.MethodPost, "/api/v1/tags"},
		{"get", http.MethodGet, "/api/v1/tags/some-id"},
		{"update", http.MethodPut, "/api/v1/tags/some-id"},
		{"delete", http.MethodDelete, "/api/v1/tags/some-id"},
		{"list", http.MethodGet, "/api/v1/tags"},
		{"children", http.MethodGet, "/api/v1/tags/some-id/children"},
		{"hierarchy", http.MethodGet, "/api/v1/tags/some-id/hierarchy"},
		{"stats", http.MethodGet, "/api/v1/tags/some-id/stats"},
		{"notes", http.MethodGet, "/api/v1/tags/some-id/notes"},
		{"link", http.MethodPost, "/api/v1/tags/some-id/notes/note-1"},
		{"unlink", http.MethodDelete, "/api/v1/tags/some-id/notes/note-1"},
		{"by-note", http.MethodGet, "/api/v1/tags/by-note/note-1"},
		{"top", http.MethodGet, "/api/v1/tags/top"},
		{"merge", http.MethodPost, "/api/v1/tags/merge"},
		{"split", http.MethodPost, "/api/v1/tags/split"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := doRequest(r, tt.method, tt.target, nil, map[string]string{"X-Test-No-Auth": "1"})
			assert.Equal(t, http.StatusUnauthorized, w.Code)
		})
	}
}

func TestTagCRUDFlow(t *testing.T) {
	r := setupTestRouter(t)

	// Create
	raw, _ := json.Marshal(model.TagMeta{Name: "CRUD 标签"})
	w := doRequest(r, http.MethodPost, "/api/v1/tags", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)

	var createResp struct {
		Data model.TagMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &createResp))
	tagID := createResp.Data.ID

	// Get
	w = doRequest(r, http.MethodGet, "/api/v1/tags/"+tagID, nil, nil)
	require.Equal(t, http.StatusOK, w.Code)

	// Update
	updateBody := model.TagMeta{Name: "更新标签", Color: "#00ff00"}
	raw, _ = json.Marshal(updateBody)
	w = doRequest(r, http.MethodPut, "/api/v1/tags/"+tagID, raw, nil)
	require.Equal(t, http.StatusOK, w.Code)
	var updateResp struct {
		Data model.TagMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &updateResp))
	assert.Equal(t, "更新标签", updateResp.Data.Name)
	assert.Equal(t, "#00ff00", updateResp.Data.Color)

	// Delete
	w = doRequest(r, http.MethodDelete, "/api/v1/tags/"+tagID, nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	// Get after delete → 404
	w = doRequest(r, http.MethodGet, "/api/v1/tags/"+tagID, nil, nil)
	assert.Equal(t, http.StatusNotFound, w.Code)
}

func TestTagGetNotFound(t *testing.T) {
	r := setupTestRouter(t)

	w := doRequest(r, http.MethodGet, "/api/v1/tags/nonexistent", nil, nil)
	assert.Equal(t, http.StatusNotFound, w.Code)
}

func TestTagList(t *testing.T) {
	r := setupTestRouter(t)

	for _, name := range []string{"标签 A", "标签 B", "标签 C"} {
		raw, _ := json.Marshal(model.TagMeta{Name: name})
		w := doRequest(r, http.MethodPost, "/api/v1/tags", raw, nil)
		require.Equal(t, http.StatusCreated, w.Code)
	}

	w := doRequest(r, http.MethodGet, "/api/v1/tags?page=1&page_size=10", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp model.PaginatedResponse
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.Equal(t, 3, resp.Total)
}

func TestTagListWithSearch(t *testing.T) {
	r := setupTestRouter(t)

	for _, name := range []string{"Go", "Rust", "Python"} {
		raw, _ := json.Marshal(model.TagMeta{Name: name})
		w := doRequest(r, http.MethodPost, "/api/v1/tags", raw, nil)
		require.Equal(t, http.StatusCreated, w.Code)
	}

	w := doRequest(r, http.MethodGet, "/api/v1/tags?search=Rust", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp model.PaginatedResponse
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.Equal(t, 1, resp.Total)
}

func TestTagHierarchyAndChildren(t *testing.T) {
	r := setupTestRouter(t)

	// 创建父标签
	raw, _ := json.Marshal(model.TagMeta{Name: "父标签"})
	w := doRequest(r, http.MethodPost, "/api/v1/tags", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)
	var parentResp struct {
		Data model.TagMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &parentResp))

	// 创建子标签
	raw, _ = json.Marshal(model.TagMeta{Name: "子标签", ParentID: parentResp.Data.ID})
	w = doRequest(r, http.MethodPost, "/api/v1/tags", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)

	// 获取子标签列表
	w = doRequest(r, http.MethodGet, "/api/v1/tags/"+parentResp.Data.ID+"/children", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)
	var childrenResp struct {
		Data []model.TagMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &childrenResp))
	assert.Len(t, childrenResp.Data, 1)

	// 获取层级
	w = doRequest(r, http.MethodGet, "/api/v1/tags/"+parentResp.Data.ID+"/hierarchy", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)
}

func TestTagLinkUnlinkNote(t *testing.T) {
	r := setupTestRouter(t)

	// 创建标签
	raw, _ := json.Marshal(model.TagMeta{Name: "关联标签"})
	w := doRequest(r, http.MethodPost, "/api/v1/tags", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)
	var tagResp struct {
		Data model.TagMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &tagResp))

	// 创建笔记
	raw, _ = json.Marshal(model.NoteMeta{Title: "被标签的笔记"})
	w = doRequest(r, http.MethodPost, "/api/v1/metadata", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)
	var noteResp struct {
		Data model.NoteMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &noteResp))

	// 关联标签到笔记
	w = doRequest(r, http.MethodPost, "/api/v1/tags/"+tagResp.Data.ID+"/notes/"+noteResp.Data.ID, nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	// 获取标签下的笔记
	w = doRequest(r, http.MethodGet, "/api/v1/tags/"+tagResp.Data.ID+"/notes", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	// 获取笔记的标签
	w = doRequest(r, http.MethodGet, "/api/v1/tags/by-note/"+noteResp.Data.ID, nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)
	var byNoteResp struct {
		Data []model.TagMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &byNoteResp))
	assert.Len(t, byNoteResp.Data, 1)

	// 取消关联
	w = doRequest(r, http.MethodDelete, "/api/v1/tags/"+tagResp.Data.ID+"/notes/"+noteResp.Data.ID, nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)
}

func TestTagMerge(t *testing.T) {
	r := setupTestRouter(t)

	// 创建两个标签
	var tagIDs []string
	for _, name := range []string{"源标签", "目标标签"} {
		raw, _ := json.Marshal(model.TagMeta{Name: name})
		w := doRequest(r, http.MethodPost, "/api/v1/tags", raw, nil)
		require.Equal(t, http.StatusCreated, w.Code)
		var resp struct {
			Data model.TagMeta `json:"data"`
		}
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		tagIDs = append(tagIDs, resp.Data.ID)
	}

	mergeReq := struct {
		SourceTagID string `json:"source_tag_id"`
		TargetTagID string `json:"target_tag_id"`
	}{SourceTagID: tagIDs[0], TargetTagID: tagIDs[1]}
	raw, _ := json.Marshal(mergeReq)

	w := doRequest(r, http.MethodPost, "/api/v1/tags/merge", raw, nil)
	assert.Equal(t, http.StatusOK, w.Code)
}

func TestTagStats(t *testing.T) {
	r := setupTestRouter(t)

	// 创建标签
	raw, _ := json.Marshal(model.TagMeta{Name: "统计标签"})
	w := doRequest(r, http.MethodPost, "/api/v1/tags", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)
	var tagResp struct {
		Data model.TagMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &tagResp))

	// 获取统计
	w = doRequest(r, http.MethodGet, "/api/v1/tags/"+tagResp.Data.ID+"/stats", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)
}

func TestTagTopTags(t *testing.T) {
	r := setupTestRouter(t)

	for _, name := range []string{"A", "B", "C"} {
		raw, _ := json.Marshal(model.TagMeta{Name: name})
		w := doRequest(r, http.MethodPost, "/api/v1/tags", raw, nil)
		require.Equal(t, http.StatusCreated, w.Code)
	}

	w := doRequest(r, http.MethodGet, "/api/v1/tags/top?limit=2", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp struct {
		Data []model.TagMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.LessOrEqual(t, len(resp.Data), 2)
}
