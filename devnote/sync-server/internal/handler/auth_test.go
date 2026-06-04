// 测试基线 —— 建立 Rust/Go/Flutter 三层测试体系，确保架构变更不引入回归
// Auth 处理器测试：注册、登录、未授权访问

package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/devnote/sync-server/internal/config"
	"github.com/devnote/sync-server/internal/middleware"
	"github.com/devnote/sync-server/internal/model"
	"github.com/devnote/sync-server/internal/service"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func setupTestRouter(t *testing.T) (*gin.Engine, *service.AuthService) {
	gin.SetMode(gin.TestMode)

	// 使用内存 SQLite 数据库
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	require.NoError(t, err)

	// 自动迁移表结构
	err = db.AutoMigrate(&model.User{}, &model.RefreshToken{})
	require.NoError(t, err)

	// 测试配置
	cfg := &config.Config{
		JWTSecret:      "test-secret-key",
		AllowedOrigins: []string{"*"},
		RateLimit:      1000,
	}

	authService := service.NewAuthService(db, cfg)
	authHandler := NewAuthHandler(authService)

	r := gin.New()
	r.Use(middleware.CORSMiddleware(cfg.AllowedOrigins))

	// Auth routes
	auth := r.Group("/api/v1/auth")
	{
		auth.POST("/register", authHandler.Register)
		auth.POST("/login", authHandler.Login)
	}

	// Protected sync routes
	sync := r.Group("/api/v1/sync")
	sync.Use(middleware.JWTAuth(authService))
	{
		sync.GET("/status", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{"status": "ok"})
		})
	}

	return r, authService
}

func TestRegisterSuccess(t *testing.T) {
	r, _ := setupTestRouter(t)

	body := map[string]string{
		"username": "testuser",
		"password": "password123",
	}
	jsonBody, _ := json.Marshal(body)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusCreated, w.Code)

	var resp map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &resp)
	require.NoError(t, err)

	assert.NotEmpty(t, resp["id"])
	assert.Equal(t, "testuser", resp["username"])
}

func TestRegisterDuplicateUsername(t *testing.T) {
	r, _ := setupTestRouter(t)

	body := map[string]string{
		"username": "dupuser",
		"password": "password123",
	}
	jsonBody, _ := json.Marshal(body)

	// 第一次注册
	req1 := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(jsonBody))
	req1.Header.Set("Content-Type", "application/json")
	w1 := httptest.NewRecorder()
	r.ServeHTTP(w1, req1)
	assert.Equal(t, http.StatusCreated, w1.Code)

	// 第二次注册相同用户名
	req2 := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(jsonBody))
	req2.Header.Set("Content-Type", "application/json")
	w2 := httptest.NewRecorder()
	r.ServeHTTP(w2, req2)

	assert.Equal(t, http.StatusConflict, w2.Code)

	var resp map[string]interface{}
	json.Unmarshal(w2.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "already exists")
}

func TestRegisterInvalidInput(t *testing.T) {
	r, _ := setupTestRouter(t)

	tests := []struct {
		name string
		body map[string]string
	}{
		{
			name: "empty username",
			body: map[string]string{"username": "", "password": "password123"},
		},
		{
			name: "short username",
			body: map[string]string{"username": "ab", "password": "password123"},
		},
		{
			name: "short password",
			body: map[string]string{"username": "validuser", "password": "12345"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			jsonBody, _ := json.Marshal(tt.body)
			req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(jsonBody))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()
			r.ServeHTTP(w, req)

			assert.Equal(t, http.StatusBadRequest, w.Code)
		})
	}
}

func TestLoginSuccess(t *testing.T) {
	r, svc := setupTestRouter(t)

	// 先注册用户
	_, err := svc.Register("loginuser", "password123")
	require.NoError(t, err)

	// 登录
	body := map[string]string{
		"username": "loginuser",
		"password": "password123",
	}
	jsonBody, _ := json.Marshal(body)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var resp map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &resp)
	require.NoError(t, err)

	assert.Equal(t, "loginuser", resp["username"])
	assert.NotEmpty(t, resp["token"])
	assert.NotEmpty(t, resp["refresh_token"])
	assert.Equal(t, float64(3600), resp["expires_in"])
}

func TestLoginInvalidCredentials(t *testing.T) {
	r, svc := setupTestRouter(t)

	// 先注册用户
	_, err := svc.Register("creduser", "correctpassword")
	require.NoError(t, err)

	// 用错误密码登录
	body := map[string]string{
		"username": "creduser",
		"password": "wrongpassword",
	}
	jsonBody, _ := json.Marshal(body)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "invalid credentials")
}

func TestLoginNonexistentUser(t *testing.T) {
	r, _ := setupTestRouter(t)

	body := map[string]string{
		"username": "nonexistent",
		"password": "password123",
	}
	jsonBody, _ := json.Marshal(body)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestUnauthorizedAccess(t *testing.T) {
	r, _ := setupTestRouter(t)

	// 不带 token 访问受保护的 sync endpoint
	req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/status", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "authorization header required")
}

func TestUnauthorizedAccessInvalidToken(t *testing.T) {
	r, _ := setupTestRouter(t)

	// 带无效 token 访问受保护的 sync endpoint
	req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/status", nil)
	req.Header.Set("Authorization", "Bearer invalid-token")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "invalid token")
}

func TestAuthorizedAccessWithValidToken(t *testing.T) {
	r, svc := setupTestRouter(t)

	// 注册并登录获取 token
	_, err := svc.Register("authtest", "password123")
	require.NoError(t, err)

	_, token, err := svc.Login("authtest", "password123")
	require.NoError(t, err)

	// 带有效 token 访问受保护的 endpoint
	req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/status", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Equal(t, "ok", resp["status"])
}