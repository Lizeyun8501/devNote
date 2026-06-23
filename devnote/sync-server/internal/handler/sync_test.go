package handler

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/devnote/sync-server/internal/service"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestSyncUnauthorized(t *testing.T) {
	env := setupFullRouter(t)

	tests := []struct {
		name   string
		method string
		target string
	}{
		{"push", http.MethodPost, "/api/v1/sync/push"},
		{"pull", http.MethodPost, "/api/v1/sync/pull"},
		{"status", http.MethodGet, "/api/v1/sync/status"},
		{"resolve-conflict", http.MethodPost, "/api/v1/sync/resolve-conflict"},
		{"history", http.MethodGet, "/api/v1/sync/notes/note-1/history"},
		{"version", http.MethodGet, "/api/v1/sync/notes/note-1/versions/1"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := doRequestFull(env.router, tt.method, tt.target, nil, map[string]string{"X-Test-No-Auth": "1"})
			assert.Equal(t, http.StatusUnauthorized, w.Code)
		})
	}
}

func TestSyncPushSuccess(t *testing.T) {
	env := setupFullRouter(t)

	body := service.PushRequest{
		DeviceID: "device-1",
		Records: []service.SyncRecordInput{
			{NoteID: "note-1", Action: "create", Version: 0, Payload: `{"title":"测试笔记"}`},
		},
	}
	raw, _ := json.Marshal(body)

	w := doRequestFull(env.router, http.MethodPost, "/api/v1/sync/push", raw, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp service.PushResponse
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.Equal(t, 1, resp.Processed)
	assert.Empty(t, resp.Conflicts)
}

func TestSyncPushInvalidJSON(t *testing.T) {
	env := setupFullRouter(t)

	w := doRequestFull(env.router, http.MethodPost, "/api/v1/sync/push", []byte("{bad-json"), nil)
	assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestSyncPushMissingDeviceID(t *testing.T) {
	env := setupFullRouter(t)

	// 缺少 device_id（binding:"required"）
	body := map[string]interface{}{
		"records": []map[string]interface{}{
			{"note_id": "note-1", "action": "create"},
		},
	}
	raw, _ := json.Marshal(body)

	w := doRequestFull(env.router, http.MethodPost, "/api/v1/sync/push", raw, nil)
	assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestSyncPullSuccess(t *testing.T) {
	env := setupFullRouter(t)

	// 先 push 一条数据
	pushBody := service.PushRequest{
		DeviceID: "device-1",
		Records: []service.SyncRecordInput{
			{NoteID: "note-pull", Action: "create", Version: 0, Payload: "content"},
		},
	}
	raw, _ := json.Marshal(pushBody)
	w := doRequestFull(env.router, http.MethodPost, "/api/v1/sync/push", raw, nil)
	require.Equal(t, http.StatusOK, w.Code)

	// pull
	pullBody := service.PullRequest{DeviceID: "device-1", SinceVer: 0}
	raw, _ = json.Marshal(pullBody)
	w = doRequestFull(env.router, http.MethodPost, "/api/v1/sync/pull", raw, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp service.PullResponse
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.GreaterOrEqual(t, len(resp.Records), 1)
}

func TestSyncPullInvalidLimit(t *testing.T) {
	env := setupFullRouter(t)

	tests := []struct {
		name   string
		limit  string
	}{
		{"non-numeric", "abc"},
		{"zero", "0"},
		{"negative", "-1"},
		{"too-large", "1001"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			body := service.PullRequest{DeviceID: "device-1"}
			raw, _ := json.Marshal(body)
			w := doRequestFull(env.router, http.MethodPost, "/api/v1/sync/pull?limit="+tt.limit, raw, nil)
			assert.Equal(t, http.StatusBadRequest, w.Code)
		})
	}
}

func TestSyncStatusMissingDeviceID(t *testing.T) {
	env := setupFullRouter(t)

	w := doRequestFull(env.router, http.MethodGet, "/api/v1/sync/status", nil, nil)
	assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestSyncStatusNonExistentDevice(t *testing.T) {
	env := setupFullRouter(t)

	// GetStatus 对不存在的设备返回默认状态（LastSyncVer=0），而非错误
	w := doRequestFull(env.router, http.MethodGet, "/api/v1/sync/status?device_id=nonexistent", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp service.SyncStatus
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.Equal(t, "nonexistent", resp.DeviceID)
	assert.Equal(t, int64(0), resp.LastSyncVer)
}

func TestSyncGetNoteHistory(t *testing.T) {
	env := setupFullRouter(t)

	// 先 push 两条版本
	for i, payload := range []string{"v1-content", "v2-content"} {
		pushBody := service.PushRequest{
			DeviceID: "device-1",
			Records: []service.SyncRecordInput{
				{NoteID: "history-note", Action: "update", Version: int64(i), Payload: payload},
			},
		}
		raw, _ := json.Marshal(pushBody)
		w := doRequestFull(env.router, http.MethodPost, "/api/v1/sync/push", raw, nil)
		require.Equal(t, http.StatusOK, w.Code)
	}

	// 获取历史
	w := doRequestFull(env.router, http.MethodGet, "/api/v1/sync/notes/history-note/history?limit=10", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp struct {
		Versions []struct {
			Version int64 `json:"version"`
			Content string `json:"content"`
		} `json:"versions"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.Len(t, resp.Versions, 2)
}

func TestSyncGetNoteHistoryInvalidLimit(t *testing.T) {
	env := setupFullRouter(t)

	w := doRequestFull(env.router, http.MethodGet, "/api/v1/sync/notes/note-1/history?limit=abc", nil, nil)
	assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestSyncGetNoteVersionNotFound(t *testing.T) {
	env := setupFullRouter(t)

	w := doRequestFull(env.router, http.MethodGet, "/api/v1/sync/notes/nonexistent/versions/1", nil, nil)
	assert.Equal(t, http.StatusNotFound, w.Code)
}

func TestSyncGetNoteVersionInvalidVersion(t *testing.T) {
	env := setupFullRouter(t)

	w := doRequestFull(env.router, http.MethodGet, "/api/v1/sync/notes/note-1/versions/abc", nil, nil)
	assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestSyncResolveConflict(t *testing.T) {
	env := setupFullRouter(t)

	body := service.ConflictResolution{
		NoteID:     "conflict-note",
		Version:    1,
		ChosenData: "resolved-content",
	}
	raw, _ := json.Marshal(body)

	w := doRequestFull(env.router, http.MethodPost, "/api/v1/sync/resolve-conflict", raw, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp map[string]string
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.Equal(t, "resolved", resp["status"])
}

func TestSyncResolveConflictInvalidJSON(t *testing.T) {
	env := setupFullRouter(t)

	w := doRequestFull(env.router, http.MethodPost, "/api/v1/sync/resolve-conflict", []byte("{bad"), nil)
	assert.Equal(t, http.StatusBadRequest, w.Code)
}
