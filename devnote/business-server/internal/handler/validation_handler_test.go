package handler

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/devnote/business-server/internal/model"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestValidationUnauthorized(t *testing.T) {
	r := setupTestRouter(t)

	tests := []struct {
		name   string
		method string
		target string
	}{
		{"validate-note", http.MethodGet, "/api/v1/validate/note/some-id"},
		{"validate-folder", http.MethodGet, "/api/v1/validate/folder/some-id"},
		{"validate-tag", http.MethodGet, "/api/v1/validate/tag/some-id"},
		{"validate-knowledge", http.MethodGet, "/api/v1/validate/knowledge/some-id"},
		{"create-rule", http.MethodPost, "/api/v1/validate/rules"},
		{"list-rules", http.MethodGet, "/api/v1/validate/rules"},
		{"update-rule", http.MethodPut, "/api/v1/validate/rules/some-id"},
		{"delete-rule", http.MethodDelete, "/api/v1/validate/rules/some-id"},
		{"create-business-rule", http.MethodPost, "/api/v1/validate/business-rules"},
		{"list-business-rules", http.MethodGet, "/api/v1/validate/business-rules"},
		{"update-business-rule", http.MethodPut, "/api/v1/validate/business-rules/some-id"},
		{"delete-business-rule", http.MethodDelete, "/api/v1/validate/business-rules/some-id"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := doRequest(r, tt.method, tt.target, nil, map[string]string{"X-Test-No-Auth": "1"})
			assert.Equal(t, http.StatusUnauthorized, w.Code)
		})
	}
}

func TestValidationValidateNoteSuccess(t *testing.T) {
	r := setupTestRouter(t)

	// 先创建笔记
	noteID := createTestNote(t, r)

	w := doRequest(r, http.MethodGet, "/api/v1/validate/note/"+noteID, nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp struct {
		Data model.ValidationReport `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.Equal(t, noteID, resp.Data.TargetID)
	assert.Equal(t, "note", resp.Data.Type)
}

func TestValidationValidateNoteNotFound(t *testing.T) {
	r := setupTestRouter(t)

	w := doRequest(r, http.MethodGet, "/api/v1/validate/note/nonexistent", nil, nil)
	assert.Equal(t, http.StatusNotFound, w.Code)
}

func TestValidationValidateFolderNotFound(t *testing.T) {
	r := setupTestRouter(t)

	// ValidateFolder 不预检文件夹是否存在，而是直接运行循环/深度校验，
	// 对不存在的文件夹返回通过的报告（service 层行为）。
	w := doRequest(r, http.MethodGet, "/api/v1/validate/folder/nonexistent", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)
}

func TestValidationValidateTagNotFound(t *testing.T) {
	r := setupTestRouter(t)

	w := doRequest(r, http.MethodGet, "/api/v1/validate/tag/nonexistent", nil, nil)
	assert.Equal(t, http.StatusNotFound, w.Code)
}

func TestValidationRuleCRUDFlow(t *testing.T) {
	r := setupTestRouter(t)

	// Create
	body := model.ValidationRule{
		Name:        "标题必填",
		Description: "笔记标题不能为空",
		Category:    "structure",
		RuleType:    "required",
		Pattern:     ".+",
		Severity:     "error",
		IsEnabled:    true,
	}
	raw, _ := json.Marshal(body)
	w := doRequest(r, http.MethodPost, "/api/v1/validate/rules", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)

	var createResp struct {
		Data model.ValidationRule `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &createResp))
	ruleID := createResp.Data.ID
	require.NotEmpty(t, ruleID)

	// List
	w = doRequest(r, http.MethodGet, "/api/v1/validate/rules", nil, nil)
	require.Equal(t, http.StatusOK, w.Code)
	var listResp struct {
		Data []model.ValidationRule `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &listResp))
	assert.Len(t, listResp.Data, 1)

	// Update
	updateBody := model.ValidationRule{
		Name:     "更新规则",
		Severity: "warning",
		IsEnabled: false,
	}
	raw, _ = json.Marshal(updateBody)
	w = doRequest(r, http.MethodPut, "/api/v1/validate/rules/"+ruleID, raw, nil)
	require.Equal(t, http.StatusOK, w.Code)
	var updateResp struct {
		Data model.ValidationRule `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &updateResp))
	assert.Equal(t, "更新规则", updateResp.Data.Name)

	// Delete
	w = doRequest(r, http.MethodDelete, "/api/v1/validate/rules/"+ruleID, nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	// List after delete
	w = doRequest(r, http.MethodGet, "/api/v1/validate/rules", nil, nil)
	require.Equal(t, http.StatusOK, w.Code)
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &listResp))
	assert.Empty(t, listResp.Data)
}

func TestValidationRuleCreateInvalidJSON(t *testing.T) {
	r := setupTestRouter(t)

	w := doRequest(r, http.MethodPost, "/api/v1/validate/rules", []byte("{bad-json"), nil)
	assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestValidationBusinessRuleCRUDFlow(t *testing.T) {
	r := setupTestRouter(t)

	// Create
	body := model.BusinessRule{
		Name:       "自动归档",
		Expression: "modified_at < now() - 30d",
		Action:     "archive",
		Priority:   1,
		IsEnabled:  true,
	}
	raw, _ := json.Marshal(body)
	w := doRequest(r, http.MethodPost, "/api/v1/validate/business-rules", raw, nil)
	require.Equal(t, http.StatusCreated, w.Code)

	var createResp struct {
		Data model.BusinessRule `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &createResp))
	ruleID := createResp.Data.ID
	require.NotEmpty(t, ruleID)

	// List
	w = doRequest(r, http.MethodGet, "/api/v1/validate/business-rules", nil, nil)
	require.Equal(t, http.StatusOK, w.Code)
	var listResp struct {
		Data []model.BusinessRule `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &listResp))
	assert.Len(t, listResp.Data, 1)

	// Update
	updateBody := model.BusinessRule{
		Name:       "更新业务规则",
		Expression: "modified_at < now() - 60d",
		Action:     "archive",
		Priority:   2,
		IsEnabled:  false,
	}
	raw, _ = json.Marshal(updateBody)
	w = doRequest(r, http.MethodPut, "/api/v1/validate/business-rules/"+ruleID, raw, nil)
	require.Equal(t, http.StatusOK, w.Code)
	var updateResp struct {
		Data model.BusinessRule `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &updateResp))
	assert.Equal(t, "更新业务规则", updateResp.Data.Name)
	assert.Equal(t, 2, updateResp.Data.Priority)

	// Delete
	w = doRequest(r, http.MethodDelete, "/api/v1/validate/business-rules/"+ruleID, nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	// List after delete
	w = doRequest(r, http.MethodGet, "/api/v1/validate/business-rules", nil, nil)
	require.Equal(t, http.StatusOK, w.Code)
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &listResp))
	assert.Empty(t, listResp.Data)
}

func TestValidationBusinessRuleCreateInvalidJSON(t *testing.T) {
	r := setupTestRouter(t)

	w := doRequest(r, http.MethodPost, "/api/v1/validate/business-rules", []byte("{bad-json"), nil)
	assert.Equal(t, http.StatusBadRequest, w.Code)
}
