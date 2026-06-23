package handler

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/devnote/sync-server/internal/service"
	"github.com/gin-gonic/gin"
	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/zap"
)

func TestEmailUnauthorized(t *testing.T) {
	env := setupFullRouter(t)

	// email/alias 端点不在 handler 层检查 user_id（依赖 JWT 中间件），
	// 因此此处仅验证 webhook 路径在无鉴权头时仍可访问（webhook 使用签名校验而非 JWT）。
	// 受保护端点的鉴权由 JWTAuth 中间件保证，已在 auth_test.go 覆盖。
	w := doRequestFull(env.router, http.MethodPost, "/webhooks/email", []byte("{bad-json"), map[string]string{"X-Test-No-Auth": "1"})
	// webhook 无需 JWT，但 body 无效 JSON 会返回 400
	assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestEmailGetAliasCreatesNew(t *testing.T) {
	env := setupFullRouter(t)

	// 首次获取别名 —— 不存在时自动创建
	w := doRequestFull(env.router, http.MethodGet, "/api/v1/email/alias", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)

	var resp map[string]interface{}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.NotEmpty(t, resp["alias"])
	assert.NotEmpty(t, resp["email_addr"])
	assert.Equal(t, true, resp["active"])
}

func TestEmailGetAliasReturnsExisting(t *testing.T) {
	env := setupFullRouter(t)

	// 第一次获取
	w1 := doRequestFull(env.router, http.MethodGet, "/api/v1/email/alias", nil, nil)
	require.Equal(t, http.StatusOK, w1.Code)
	var resp1 map[string]interface{}
	require.NoError(t, json.Unmarshal(w1.Body.Bytes(), &resp1))

	// 第二次获取 —— 应返回相同别名
	w2 := doRequestFull(env.router, http.MethodGet, "/api/v1/email/alias", nil, nil)
	require.Equal(t, http.StatusOK, w2.Code)
	var resp2 map[string]interface{}
	require.NoError(t, json.Unmarshal(w2.Body.Bytes(), &resp2))

	assert.Equal(t, resp1["alias"], resp2["alias"])
}

func TestEmailRegenerateAlias(t *testing.T) {
	env := setupFullRouter(t)

	// 先获取初始别名
	w := doRequestFull(env.router, http.MethodGet, "/api/v1/email/alias", nil, nil)
	require.Equal(t, http.StatusOK, w.Code)
	var oldResp map[string]interface{}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &oldResp))
	oldAlias := oldResp["alias"].(string)

	// 重新生成
	w = doRequestFull(env.router, http.MethodPost, "/api/v1/email/alias/regenerate", nil, nil)
	assert.Equal(t, http.StatusOK, w.Code)
	var newResp map[string]interface{}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &newResp))

	assert.NotEqual(t, oldAlias, newResp["alias"])
	assert.Equal(t, true, newResp["active"])
}

func TestEmailWebhookNoSecret(t *testing.T) {
	// webhookSecret 为空字符串时跳过签名校验（测试环境默认配置）
	env := setupFullRouter(t)

	// 先为测试用户创建邮件别名，使 webhook 能找到对应用户
	w := doRequestFull(env.router, http.MethodGet, "/api/v1/email/alias", nil, nil)
	require.Equal(t, http.StatusOK, w.Code)
	var aliasResp map[string]interface{}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &aliasResp))
	emailAddr := aliasResp["email_addr"].(string)

	body := map[string]string{
		"to":        emailAddr,
		"from":      "sender@example.com",
		"subject":   "测试邮件",
		"text_body": "邮件正文",
		"html_body": "<p>邮件正文</p>",
	}
	raw, _ := json.Marshal(body)

	w = doRequestFull(env.router, http.MethodPost, "/webhooks/email", raw, map[string]string{"X-Test-No-Auth": "1"})
	assert.Equal(t, http.StatusOK, w.Code)

	var resp map[string]string
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	assert.Equal(t, "processed", resp["message"])
}

func TestEmailWebhookInvalidJSON(t *testing.T) {
	env := setupFullRouter(t)

	w := doRequestFull(env.router, http.MethodPost, "/webhooks/email", []byte("{bad-json"), map[string]string{"X-Test-No-Auth": "1"})
	assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestEmailWebhookWithSignature(t *testing.T) {
	// 验证 HMAC-SHA256 签名校验逻辑：构造带 webhookSecret 的独立路由
	gin.SetMode(gin.TestMode)
	db, err := sqlx.Open("sqlite3", ":memory:")
	require.NoError(t, err)
	t.Cleanup(func() { _ = db.Close() })
	_, err = db.Exec(fullTestSchema)
	require.NoError(t, err)

	secret := "webhook-secret-key"
	syncSvc := service.NewSyncService(db, nil)
	emailSvc, err := service.NewEmailService(db, syncSvc, "test.devnote.app")
	require.NoError(t, err)
	signedHandler := NewEmailHandler(emailSvc, secret, zap.NewNop())

	// 先通过无密钥 handler 创建别名，使 webhook 能找到对应用户
	plainHandler := NewEmailHandler(emailSvc, "", zap.NewNop())
	plainRouter := gin.New()
	plainRouter.Use(func(c *gin.Context) { c.Set("user_id", testUserID); c.Next() })
	plainRouter.GET("/api/v1/email/alias", plainHandler.GetUserAlias)
	aliasReq := httptest.NewRequest(http.MethodGet, "/api/v1/email/alias", nil)
	aliasW := httptest.NewRecorder()
	plainRouter.ServeHTTP(aliasW, aliasReq)
	require.Equal(t, http.StatusOK, aliasW.Code)
	var aliasResp map[string]interface{}
	require.NoError(t, json.Unmarshal(aliasW.Body.Bytes(), &aliasResp))
	emailAddr := aliasResp["email_addr"].(string)

	r := gin.New()
	r.POST("/webhooks/email", signedHandler.IncomingEmailWebhook)

	body := []byte(`{"to":"` + emailAddr + `","from":"s@e.com","subject":"t","text_body":"b"}`)

	// 计算正确签名
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	validSig := hex.EncodeToString(mac.Sum(nil))

	t.Run("valid signature", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/webhooks/email", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Webhook-Signature", validSig)
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
	})

	t.Run("missing signature", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/webhooks/email", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		assert.Equal(t, http.StatusUnauthorized, w.Code)
	})

	t.Run("invalid signature", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/webhooks/email", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Webhook-Signature", "deadbeef")
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		assert.Equal(t, http.StatusUnauthorized, w.Code)
	})
}
