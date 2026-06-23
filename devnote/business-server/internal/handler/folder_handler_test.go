package handler

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/devnote/business-server/internal/model"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestFolderCreateSuccess(t *testing.T) {
	r := setupTestRouter(t)

	body := model.FolderMeta{Name: "我的文件夹", Description: "测试目录"}
	raw, _ := json.Marshal(body)

	w := doRequest(r, http.MethodPost, "/api/v1/folders", raw, nil)
	assert.Equal(t, http.StatusCreated, w.Code)

	var resp struct {
		Data model.FolderMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.NotEmpty(t, resp.Data.ID)
	assert.Equal(t, "我的文件夹", resp.Data.Name)
	assert.Equal(t, testAuthUser, resp.Data.UserID)
	assert.Contains(t, resp.Data.Path, "我的文件夹")
}

func TestFolderCreateMissingName(t *testing.T) {
	r := setupTestRouter(t)

	body := model.FolderMeta{Description: "无名称"}
	raw, _ := json.Marshal(body)

	w := doRequest(r, http.MethodPost, "/api/v1/folders", raw, nil)
	assert.Equal(t, http.StatusInternalServerError, w.Code)
}

func TestFolderUnauthorized(t *testing.T) {
	r := setupTestRouter(t)

	tests := []struct {
		name   string
		method string
		target string
	}{
		{"create", http.MethodPost, "/api/v1/folders"},
		{"get", http.MethodGet, "/api/v1/folders/some-id"},
		{"update", http.MethodPut, "/api/v1/folders/some-id"},
		{"delete", http.MethodDelete, "/api/v1/folders/some-id"},
		{"list", http.MethodGet, "/api/v1/folders"},
		{"tree", http.MethodGet, "/api/v1/folders/tree"},
		{"path", http.MethodGet, "/api/v1/folders/some-id/path"},
		{"notes", http.MethodGet, "/api/v1/folders/some-id/notes"},
		{"move", http.MethodPost, "/api/v1/folders/some-id/move"},
		{"copy", http.MethodPost, "/api/v1/folders/some-id/copy"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := doRequest(r, tt.method, tt.target, nil, map[string]string{"X-Test-No-Auth": "1"})
			assert.Equal(t, http.StatusUnauthorized, w.Code)
		})
	}
}

func TestFolderCRUDFlow(t *testing.T) {
	r := setupTestRouter(t)

	// Create
	raw, _ := json.Marshal(model.FolderMeta{Name: "CRUD 文件夹"})
	w := doRequest(r, http.MethodPost, "/api/v1/folders", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)

	var createResp struct {
		Data model.FolderMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &createResp))
	folderID := createResp.Data.ID

	// Get
	w = doRequest(r, http.MethodGet, "/api/v1/folders/"+folderID, nil, nil)
	require.Equal(t, http.StatusOK, w.Code)

	// Update
	updateBody := model.FolderMeta{Name: "更新文件夹"}
	raw, _ = json.Marshal(updateBody)
	w = doRequest(r, http.MethodPut, "/api/v1/folders/"+folderID, raw, nil)
	require.Equal(t, http.StatusOK, w.Code)
	var updateResp struct {
		Data model.FolderMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &updateResp))
	assert.Equal(t, "更新文件夹", updateResp.Data.Name)

	// Delete
	w = doRequest(r, http.MethodDelete, "/api/v1/folders/"+folderID, nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	// Get after delete → 404
	w = doRequest(r, http.MethodGet, "/api/v1/folders/"+folderID, nil, nil)
	assert.Equal(t, http.StatusNotFound, w.Code)
}

func TestFolderGetNotFound(t *testing.T) {
	r := setupTestRouter(t)

	w := doRequest(r, http.MethodGet, "/api/v1/folders/nonexistent", nil, nil)
	assert.Equal(t, http.StatusNotFound, w.Code)
}

func TestFolderListByParent(t *testing.T) {
	r := setupTestRouter(t)

	// 创建父文件夹
	raw, _ := json.Marshal(model.FolderMeta{Name: "父文件夹"})
	w := doRequest(r, http.MethodPost, "/api/v1/folders", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)
	var parentResp struct {
		Data model.FolderMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &parentResp))
	parentID := parentResp.Data.ID

	// 创建两个子文件夹
	for _, name := range []string{"子文件夹 A", "子文件夹 B"} {
		raw, _ := json.Marshal(model.FolderMeta{Name: name, ParentID: parentID})
		w := doRequest(r, http.MethodPost, "/api/v1/folders", raw, nil)
		require.Equal(t, http.StatusCreated, w.Code)
	}

	// 按父 ID 列出
	w = doRequest(r, http.MethodGet, "/api/v1/folders?parent_id="+parentID, nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp struct {
		Data []model.FolderMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.Len(t, resp.Data, 2)
}

func TestFolderGetTree(t *testing.T) {
	r := setupTestRouter(t)

	// 创建根文件夹
	raw, _ := json.Marshal(model.FolderMeta{Name: "根"})
	w := doRequest(r, http.MethodPost, "/api/v1/folders", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)
	var rootResp struct {
		Data model.FolderMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &rootResp))

	// 创建子文件夹
	raw, _ = json.Marshal(model.FolderMeta{Name: "子", ParentID: rootResp.Data.ID})
	w = doRequest(r, http.MethodPost, "/api/v1/folders", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)

	// 获取树
	w = doRequest(r, http.MethodGet, "/api/v1/folders/tree", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)
}

func TestFolderResolvePath(t *testing.T) {
	r := setupTestRouter(t)

	// 创建文件夹
	raw, _ := json.Marshal(model.FolderMeta{Name: "路径测试"})
	w := doRequest(r, http.MethodPost, "/api/v1/folders", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)
	var createResp struct {
		Data model.FolderMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &createResp))

	// 解析路径
	w = doRequest(r, http.MethodGet, "/api/v1/folders/"+createResp.Data.ID+"/path", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp struct {
		Data struct {
			Path string `json:"path"`
		} `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.Contains(t, resp.Data.Path, "路径测试")
}

func TestFolderMove(t *testing.T) {
	r := setupTestRouter(t)

	// 创建两个文件夹
	var ids []string
	for _, name := range []string{"源文件夹", "目标文件夹"} {
		raw, _ := json.Marshal(model.FolderMeta{Name: name})
		w := doRequest(r, http.MethodPost, "/api/v1/folders", raw, nil)
		require.Equal(t, http.StatusCreated, w.Code)
		var resp struct {
			Data model.FolderMeta `json:"data"`
		}
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		ids = append(ids, resp.Data.ID)
	}

	// 移动 源 → 目标
	moveReq := struct {
		NewParentID string `json:"new_parent_id"`
	}{NewParentID: ids[1]}
	raw, _ := json.Marshal(moveReq)
	w := doRequest(r, http.MethodPost, "/api/v1/folders/"+ids[0]+"/move", raw, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	// 验证父 ID 已更新
	w = doRequest(r, http.MethodGet, "/api/v1/folders/"+ids[0], nil, nil)
	require.Equal(t, http.StatusOK, w.Code)
	var getResp struct {
		Data model.FolderMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &getResp))
	assert.Equal(t, ids[1], getResp.Data.ParentID)
}

func TestFolderCopy(t *testing.T) {
	r := setupTestRouter(t)

	// 创建源文件夹
	raw, _ := json.Marshal(model.FolderMeta{Name: "复制源"})
	w := doRequest(r, http.MethodPost, "/api/v1/folders", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)
	var srcResp struct {
		Data model.FolderMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &srcResp))

	// 复制到根（new_parent_id 为空）
	copyReq := struct {
		NewParentID string `json:"new_parent_id"`
	}{}
	raw, _ = json.Marshal(copyReq)
	w = doRequest(r, http.MethodPost, "/api/v1/folders/"+srcResp.Data.ID+"/copy", raw, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp struct {
		Data model.FolderMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.NotEqual(t, srcResp.Data.ID, resp.Data.ID)
	// 复制服务会在名称后追加 " (copy)"
	assert.Contains(t, resp.Data.Name, "复制源")
}

func TestFolderDeleteCascade(t *testing.T) {
	r := setupTestRouter(t)

	// 创建父文件夹
	raw, _ := json.Marshal(model.FolderMeta{Name: "父"})
	w := doRequest(r, http.MethodPost, "/api/v1/folders", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)
	var parentResp struct {
		Data model.FolderMeta `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &parentResp))

	// 创建子文件夹
	raw, _ = json.Marshal(model.FolderMeta{Name: "子", ParentID: parentResp.Data.ID})
	w = doRequest(r, http.MethodPost, "/api/v1/folders", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)

	// 级联删除父文件夹
	w = doRequest(r, http.MethodDelete, "/api/v1/folders/"+parentResp.Data.ID+"?cascade=true", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)
}
