package handler

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestShareUnauthorized(t *testing.T) {
	env := setupFullRouter(t)

	tests := []struct {
		name   string
		method string
		target string
	}{
		{"create", http.MethodPost, "/api/v1/shares"},
		{"list", http.MethodGet, "/api/v1/shares"},
		{"delete", http.MethodDelete, "/api/v1/shares/some-id"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := doRequestFull(env.router, tt.method, tt.target, nil, map[string]string{"X-Test-No-Auth": "1"})
			assert.Equal(t, http.StatusUnauthorized, w.Code)
		})
	}
}

func TestShareCreateSuccess(t *testing.T) {
	env := setupFullRouter(t)

	body := CreateShareRequest{
		NoteID:  "note-1",
		Title:   "分享的笔记",
		Content: "笔记内容",
	}
	raw, _ := json.Marshal(body)

	w := doRequestFull(env.router, http.MethodPost, "/api/v1/shares", raw, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp map[string]interface{}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.NotEmpty(t, resp["id"])
	assert.NotEmpty(t, resp["share_token"])
	assert.NotEmpty(t, resp["share_url"])
	assert.Equal(t, false, resp["has_password"])
}

func TestShareCreateWithPassword(t *testing.T) {
	env := setupFullRouter(t)

	body := CreateShareRequest{
		NoteID:   "note-2",
		Title:    "加密分享",
		Content:  "机密内容",
		Password: "secret123",
	}
	raw, _ := json.Marshal(body)

	w := doRequestFull(env.router, http.MethodPost, "/api/v1/shares", raw, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp map[string]interface{}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.Equal(t, true, resp["has_password"])
}

func TestShareCreateWithExpiry(t *testing.T) {
	env := setupFullRouter(t)

	body := CreateShareRequest{
		NoteID:    "note-3",
		Title:     "限时分享",
		Content:   "内容",
		ExpiresIn: 3600, // 1 小时后过期
	}
	raw, _ := json.Marshal(body)

	w := doRequestFull(env.router, http.MethodPost, "/api/v1/shares", raw, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp map[string]interface{}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.NotNil(t, resp["expires_at"])
}

func TestShareCreateMissingFields(t *testing.T) {
	env := setupFullRouter(t)

	tests := []struct {
		name string
		body map[string]interface{}
	}{
		{"missing-note-id", map[string]interface{}{"title": "t", "content": "c"}},
		{"missing-title", map[string]interface{}{"note_id": "n", "content": "c"}},
		{"missing-content", map[string]interface{}{"note_id": "n", "title": "t"}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			raw, _ := json.Marshal(tt.body)
			w := doRequestFull(env.router, http.MethodPost, "/api/v1/shares", raw, nil)
			assert.Equal(t, http.StatusBadRequest, w.Code)
		})
	}
}

func TestShareListAndDelete(t *testing.T) {
	env := setupFullRouter(t)

	// 创建两个分享
	var shareTokens []string
	for _, title := range []string{"分享 A", "分享 B"} {
		body := CreateShareRequest{NoteID: "note-x", Title: title, Content: "content"}
		raw, _ := json.Marshal(body)
		w := doRequestFull(env.router, http.MethodPost, "/api/v1/shares", raw, nil)
		require.Equal(t, http.StatusOK, w.Code)
		var resp map[string]interface{}
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		shareTokens = append(shareTokens, resp["id"].(string))
	}

	// 列出
	w := doRequestFull(env.router, http.MethodGet, "/api/v1/shares", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)
	var listResp struct {
		Shares []map[string]interface{} `json:"shares"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &listResp))
	assert.Len(t, listResp.Shares, 2)

	// 删除第一个
	w = doRequestFull(env.router, http.MethodDelete, "/api/v1/shares/"+shareTokens[0], nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	// 再次列出，应剩 1 个
	w = doRequestFull(env.router, http.MethodGet, "/api/v1/shares", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &listResp))
	assert.Len(t, listResp.Shares, 1)
}

func TestShareGetSharedNote(t *testing.T) {
	env := setupFullRouter(t)

	// 创建分享
	body := CreateShareRequest{NoteID: "note-public", Title: "公开笔记", Content: "公开内容"}
	raw, _ := json.Marshal(body)
	w := doRequestFull(env.router, http.MethodPost, "/api/v1/shares", raw, nil)
	require.Equal(t, http.StatusOK, w.Code)
	var createResp map[string]interface{}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &createResp))
	shareURL := createResp["share_url"].(string)
	token := shareURL[len("/s/"):]

	// 公开访问（无需认证）—— 使用 X-Test-No-Auth 模拟无鉴权
	w = doRequestFull(env.router, http.MethodGet, "/s/"+token, nil, map[string]string{"X-Test-No-Auth": "1"})
	assert.Equal(t, http.StatusOK, w.Code)

	var resp map[string]interface{}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.Equal(t, "公开笔记", resp["title"])
	assert.Equal(t, "公开内容", resp["content"])
	assert.Equal(t, false, resp["has_password"])
}

func TestShareGetSharedNoteNotFound(t *testing.T) {
	env := setupFullRouter(t)

	w := doRequestFull(env.router, http.MethodGet, "/s/nonexistent-token", nil, map[string]string{"X-Test-No-Auth": "1"})
	assert.Equal(t, http.StatusNotFound, w.Code)
}

func TestShareGetSharedNoteWithPassword(t *testing.T) {
	env := setupFullRouter(t)

	// 创建带密码的分享
	body := CreateShareRequest{
		NoteID:   "note-protected",
		Title:    "受保护笔记",
		Content:  "机密",
		Password: "mypassword",
	}
	raw, _ := json.Marshal(body)
	w := doRequestFull(env.router, http.MethodPost, "/api/v1/shares", raw, nil)
	require.Equal(t, http.StatusOK, w.Code)
	var createResp map[string]interface{}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &createResp))
	token := createResp["share_url"].(string)[len("/s/"):]

	// 不带密码访问 —— 应失败
	w = doRequestFull(env.router, http.MethodGet, "/s/"+token, nil, map[string]string{"X-Test-No-Auth": "1"})
	assert.Equal(t, http.StatusNotFound, w.Code)

	// 带正确密码访问
	w = doRequestFull(env.router, http.MethodGet, "/s/"+token+"?password=mypassword", nil, map[string]string{"X-Test-No-Auth": "1"})
	assert.Equal(t, http.StatusOK, w.Code)

	var resp map[string]interface{}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.Equal(t, "受保护笔记", resp["title"])
	assert.Equal(t, true, resp["has_password"])
}
