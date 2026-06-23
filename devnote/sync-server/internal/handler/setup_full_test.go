// 测试基线 —— 为 sync-server 全部 handler 补齐表驱动测试
// 共享测试夹具：内存 SQLite（全量 schema）+ 全量路由 + 测试鉴权中间件

package handler

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/devnote/sync-server/internal/config"
	"github.com/devnote/sync-server/internal/service"
	"github.com/gin-gonic/gin"
	"github.com/jmoiron/sqlx"
	_ "github.com/mattn/go-sqlite3" // 注册 sqlite3 驱动供测试使用
	"github.com/stretchr/testify/require"
	"go.uber.org/zap"
)

// fullTestSchema 与 sync-server migrations/000001_init_schema.up.sql 一致
const fullTestSchema = `
CREATE TABLE IF NOT EXISTS users (
    id            TEXT PRIMARY KEY,
    username      TEXT NOT NULL UNIQUE,
    password      TEXT NOT NULL DEFAULT '',
    srp_salt      BLOB,
    srp_verifier  BLOB,
    srp_enabled   INTEGER NOT NULL DEFAULT 0,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at    DATETIME
);
CREATE TABLE IF NOT EXISTS devices (
    id             TEXT PRIMARY KEY,
    user_id        TEXT NOT NULL,
    device_name    TEXT NOT NULL DEFAULT '',
    device_type    TEXT NOT NULL DEFAULT '',
    last_sync_at   DATETIME,
    last_sync_ver  INTEGER NOT NULL DEFAULT 0,
    created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at     DATETIME
);
CREATE TABLE IF NOT EXISTS sync_records (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL,
    device_id   TEXT NOT NULL DEFAULT '',
    note_id     TEXT NOT NULL,
    action      TEXT NOT NULL DEFAULT 'update',
    version     INTEGER NOT NULL,
    timestamp   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    payload     TEXT NOT NULL DEFAULT '',
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at  DATETIME
);
CREATE TABLE IF NOT EXISTS note_snapshots (
    id          TEXT PRIMARY KEY,
    note_id     TEXT NOT NULL,
    user_id     TEXT NOT NULL,
    version     INTEGER NOT NULL,
    content     TEXT NOT NULL DEFAULT '',
    checksum    TEXT NOT NULL DEFAULT '',
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at  DATETIME
);
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL,
    token       TEXT NOT NULL UNIQUE,
    expires_at  DATETIME NOT NULL,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked     INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS shared_notes (
    id             TEXT PRIMARY KEY,
    user_id        TEXT NOT NULL,
    note_id        TEXT NOT NULL,
    share_token    TEXT NOT NULL UNIQUE,
    title          TEXT NOT NULL DEFAULT '',
    content        TEXT NOT NULL DEFAULT '',
    password_hash  TEXT NOT NULL DEFAULT '',
    has_password   INTEGER NOT NULL DEFAULT 0,
    expires_at     DATETIME,
    view_count     INTEGER NOT NULL DEFAULT 0,
    created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at     DATETIME
);
CREATE TABLE IF NOT EXISTS user_email_aliases (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL,
    alias       TEXT NOT NULL UNIQUE,
    email_addr  TEXT NOT NULL UNIQUE,
    active      INTEGER NOT NULL DEFAULT 1,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
`

// testUserID 标识当前测试请求所属用户。
const testUserID = "test-user-id"

// testEnv 封装测试路由与关键服务，供各 handler 测试复用。
type testEnv struct {
	router      *gin.Engine
	authService *service.AuthService
	syncService *service.SyncService
	shareService *service.ShareService
}

// setupFullRouter 构建挂载全部 handler 的 gin 路由，使用内存 SQLite。
// 鉴权通过 testAuthMiddlewareFull 直接注入 user_id，跳过 JWT 以聚焦 handler 行为。
func setupFullRouter(t *testing.T) *testEnv {
	t.Helper()
	gin.SetMode(gin.TestMode)

	db, err := sqlx.Open("sqlite3", ":memory:")
	require.NoError(t, err)
	t.Cleanup(func() { _ = db.Close() })

	_, err = db.Exec(fullTestSchema)
	require.NoError(t, err)

	cfg := &config.Config{
		JWTSecret:      "test-secret-key-at-least-32-bytes-long",
		AllowedOrigins: []string{"*"},
		RateLimit:      1000,
		EmailDomain:    "test.devnote.app",
	}

	authService := service.NewAuthService(db, cfg)
	// SyncService.Push/Pull/GetStatus 仅依赖 db，S3 传 nil 不影响这些操作
	syncService := service.NewSyncService(db, nil)
	shareService := service.NewShareService(db)
	emailService, err := service.NewEmailService(db, syncService, cfg.EmailDomain)
	require.NoError(t, err)

	logger := zap.NewNop()
	authHandler := NewAuthHandler(authService, logger)
	syncHandler := NewSyncHandler(syncService, logger)
	healthHandler := NewHealthHandler()
	clipperHandler := NewClipperHandler(syncService, logger)
	shareHandler := NewShareHandler(shareService, logger)
	emailHandler := NewEmailHandler(emailService, "", logger) // webhookSecret="" 跳过签名校验

	r := gin.New()
	r.Use(testAuthMiddlewareFull())

	r.GET("/health", healthHandler.Check)
	r.GET("/s/:token", shareHandler.GetSharedNote)
	r.POST("/webhooks/email", emailHandler.IncomingEmailWebhook)

	api := r.Group("/api/v1")
	api.Use(testAuthMiddlewareFull())
	{
		auth := api.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
		}

		sync := api.Group("/sync")
		{
			sync.POST("/push", syncHandler.Push)
			sync.POST("/pull", syncHandler.Pull)
			sync.GET("/status", syncHandler.Status)
			sync.POST("/resolve-conflict", syncHandler.ResolveConflict)
			sync.GET("/notes/:noteId/history", syncHandler.GetNoteHistory)
			sync.GET("/notes/:noteId/versions/:version", syncHandler.GetNoteVersion)
		}

		notes := api.Group("/notes")
		{
			notes.POST("/clip", clipperHandler.Clip)
		}

		shares := api.Group("/shares")
		{
			shares.POST("", shareHandler.CreateShare)
			shares.GET("", shareHandler.ListShares)
			shares.DELETE("/:shareId", shareHandler.DeleteShare)
		}

		email := api.Group("/email")
		{
			email.GET("/alias", emailHandler.GetUserAlias)
			email.POST("/alias/regenerate", emailHandler.RegenerateAlias)
		}
	}

	return &testEnv{
		router:       r,
		authService:  authService,
		syncService:  syncService,
		shareService: shareService,
	}
}

// testAuthMiddlewareFull 注入测试用户身份；通过 X-Test-No-Auth 头可模拟未鉴权。
func testAuthMiddlewareFull() gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.GetHeader("X-Test-No-Auth") == "1" {
			c.Next()
			return
		}
		c.Set("user_id", testUserID)
		c.Next()
	}
}

// doRequestFull 发起一次 HTTP 请求并返回响应记录器。
func doRequestFull(r *gin.Engine, method, target string, body []byte, headers map[string]string) *httptest.ResponseRecorder {
	var req *http.Request
	if body != nil {
		req = httptest.NewRequest(method, target, bytes.NewReader(body))
	} else {
		req = httptest.NewRequest(method, target, nil)
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	if body != nil && req.Header.Get("Content-Type") == "" {
		req.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}
