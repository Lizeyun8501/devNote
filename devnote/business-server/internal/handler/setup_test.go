// 测试基线 —— 为 business-server handler 建立表驱动测试，确保重构有安全网
// 共享测试夹具：内存 SQLite + 全量路由注册 + 测试鉴权中间件

package handler

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/devnote/business-server/internal/service"
	"github.com/gin-gonic/gin"
	"github.com/jmoiron/sqlx"
	_ "github.com/mattn/go-sqlite3" // 注册 sqlite3 驱动供测试使用
	"github.com/stretchr/testify/require"
	"go.uber.org/zap"
)

// testSchema 与 migrations/000001_init_schema.up.sql 保持一致
const testSchema = `
CREATE TABLE IF NOT EXISTS note_meta (
    id            TEXT PRIMARY KEY,
    user_id       TEXT NOT NULL,
    title         TEXT NOT NULL DEFAULT '',
    author        TEXT NOT NULL DEFAULT '',
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    word_count    INTEGER NOT NULL DEFAULT 0,
    char_count    INTEGER NOT NULL DEFAULT 0,
    format        TEXT NOT NULL DEFAULT 'markdown',
    excerpt       TEXT NOT NULL DEFAULT '',
    language      TEXT NOT NULL DEFAULT 'en',
    is_encrypted  INTEGER NOT NULL DEFAULT 0,
    content_hash  TEXT NOT NULL DEFAULT '',
    custom_fields TEXT NOT NULL DEFAULT '{}'
);
CREATE TABLE IF NOT EXISTS folder_meta (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL,
    name        TEXT NOT NULL DEFAULT '',
    parent_id   TEXT NOT NULL DEFAULT '',
    path        TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    icon        TEXT NOT NULL DEFAULT '',
    color       TEXT NOT NULL DEFAULT '',
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    note_count  INTEGER NOT NULL DEFAULT 0,
    child_count INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS tag_meta (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL,
    name        TEXT NOT NULL DEFAULT '',
    parent_id   TEXT NOT NULL DEFAULT '',
    color       TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    use_count   INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS tag_relation (
    id        TEXT PRIMARY KEY,
    tag_id    TEXT NOT NULL,
    note_id   TEXT NOT NULL,
    linked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tag_id) REFERENCES tag_meta(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS knowledge_relation (
    id              TEXT PRIMARY KEY,
    user_id         TEXT NOT NULL,
    source_note_id  TEXT NOT NULL,
    target_note_id  TEXT NOT NULL,
    weight          REAL NOT NULL DEFAULT 0.0,
    reference_count INTEGER NOT NULL DEFAULT 0,
    relation_type   TEXT NOT NULL DEFAULT 'link',
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS validation_rule (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL DEFAULT '',
    name        TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    category    TEXT NOT NULL DEFAULT '',
    rule_type   TEXT NOT NULL DEFAULT '',
    pattern     TEXT NOT NULL DEFAULT '',
    severity    TEXT NOT NULL DEFAULT 'warning',
    is_enabled  INTEGER NOT NULL DEFAULT 1,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS business_rule (
    id         TEXT PRIMARY KEY,
    user_id    TEXT NOT NULL DEFAULT '',
    name       TEXT NOT NULL DEFAULT '',
    expression TEXT NOT NULL DEFAULT '',
    action     TEXT NOT NULL DEFAULT '',
    priority   INTEGER NOT NULL DEFAULT 0,
    is_enabled INTEGER NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
`

// testAuthUser 标识当前测试请求所属用户；空字符串表示未鉴权。
const testAuthUser = "test-user-id"

// setupTestRouter 构建一个挂载全部 handler 的 gin 路由，使用内存 SQLite。
// 鉴权通过 testAuthMiddleware 直接注入 user_id，跳过 JWT 以聚焦 handler 行为。
func setupTestRouter(t *testing.T) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)

	db, err := sqlx.Open("sqlite3", ":memory:")
	require.NoError(t, err)
	t.Cleanup(func() { _ = db.Close() })

	_, err = db.Exec(testSchema)
	require.NoError(t, err)

	// 与 main.go 保持一致的服务装配
	metadataSvc := service.NewMetadataService(db)
	tagSvc := service.NewTagService(db)
	folderSvc := service.NewFolderService(db)
	validationSvc := service.NewValidationService(db, service.ValidationConfig{
		MaxTagDepth:    5,
		MaxFolderDepth: 10,
		MaxNoteSize:    10485760,
	})
	knowledgeSvc := service.NewKnowledgeService(db, service.KnowledgeConfig{
		PageRankDamping: 0.85,
		PageRankIters:   100,
	})

	logger := zap.NewNop()
	metadataHandler := NewMetadataHandler(metadataSvc, logger)
	validationHandler := NewValidationHandler(validationSvc, logger)
	tagHandler := NewTagHandler(tagSvc, logger)
	folderHandler := NewFolderHandler(folderSvc, logger)
	knowledgeHandler := NewKnowledgeHandler(knowledgeSvc, logger)
	healthHandler := NewHealthHandler(logger)

	r := gin.New()
	r.Use(testAuthMiddleware())

	r.GET("/api/v1/health", healthHandler.Check)

	api := r.Group("/api/v1")
	api.Use(testAuthMiddleware())
	{
		meta := api.Group("/metadata")
		meta.POST("", metadataHandler.Create)
		meta.GET("", metadataHandler.List)
		meta.GET("/filter", metadataHandler.Filter)
		meta.GET("/:id", metadataHandler.Get)
		meta.PUT("/:id", metadataHandler.Update)
		meta.DELETE("/:id", metadataHandler.Delete)
		meta.POST("/batch", metadataHandler.BatchCreate)
		meta.POST("/batch-delete", metadataHandler.BatchDelete)

		val := api.Group("/validate")
		val.GET("/note/:id", validationHandler.ValidateNote)
		val.GET("/folder/:id", validationHandler.ValidateFolder)
		val.GET("/tag/:id", validationHandler.ValidateTag)
		val.GET("/knowledge/:id", validationHandler.ValidateKnowledgeRelation)
		val.POST("/rules", validationHandler.CreateRule)
		val.GET("/rules", validationHandler.ListRules)
		val.PUT("/rules/:id", validationHandler.UpdateRule)
		val.DELETE("/rules/:id", validationHandler.DeleteRule)
		val.POST("/business-rules", validationHandler.CreateBusinessRule)
		val.GET("/business-rules", validationHandler.ListBusinessRules)
		val.PUT("/business-rules/:id", validationHandler.UpdateBusinessRule)
		val.DELETE("/business-rules/:id", validationHandler.DeleteBusinessRule)

		tags := api.Group("/tags")
		tags.POST("", tagHandler.Create)
		tags.GET("", tagHandler.List)
		tags.GET("/top", tagHandler.GetTopTags)
		tags.GET("/by-note/:noteId", tagHandler.GetTagsByNote)
		tags.GET("/:id", tagHandler.Get)
		tags.PUT("/:id", tagHandler.Update)
		tags.DELETE("/:id", tagHandler.Delete)
		tags.GET("/:id/children", tagHandler.GetChildren)
		tags.GET("/:id/hierarchy", tagHandler.GetHierarchy)
		tags.GET("/:id/stats", tagHandler.GetStats)
		tags.GET("/:id/notes", tagHandler.GetNotesByTag)
		tags.POST("/:id/notes/:noteId", tagHandler.LinkTag)
		tags.DELETE("/:id/notes/:noteId", tagHandler.UnlinkTag)
		tags.POST("/merge", tagHandler.MergeTags)
		tags.POST("/split", tagHandler.SplitTag)

		folders := api.Group("/folders")
		folders.POST("", folderHandler.Create)
		folders.GET("", folderHandler.List)
		folders.GET("/tree", folderHandler.GetTree)
		folders.GET("/:id", folderHandler.Get)
		folders.PUT("/:id", folderHandler.Update)
		folders.DELETE("/:id", folderHandler.Delete)
		folders.GET("/:id/path", folderHandler.ResolvePath)
		folders.GET("/:id/notes", folderHandler.GetNotesByFolder)
		folders.POST("/:id/move", folderHandler.MoveFolder)
		folders.POST("/:id/copy", folderHandler.CopyFolder)

		know := api.Group("/knowledge")
		know.POST("/relations", knowledgeHandler.CreateRelation)
		know.DELETE("/relations/:id", knowledgeHandler.DeleteRelation)
		know.GET("/notes/:noteId/relations", knowledgeHandler.GetRelations)
		know.GET("/graph/edges", knowledgeHandler.ComputeEdges)
		know.GET("/graph/metrics", knowledgeHandler.ComputeMetrics)
		know.GET("/graph/orphans", knowledgeHandler.FindOrphans)
		know.GET("/graph/coverage", knowledgeHandler.ComputeCoverage)
		know.GET("/suggest/:noteId", knowledgeHandler.SuggestRelated)
		know.GET("/path", knowledgeHandler.FindShortestPath)
	}

	return r
}

// testAuthMiddleware 注入测试用户身份；通过 X-Test-No-Auth 头可模拟未鉴权。
func testAuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.GetHeader("X-Test-No-Auth") == "1" {
			c.Next()
			return
		}
		c.Set("user_id", testAuthUser)
		c.Next()
	}
}

// doRequest 发起一次 HTTP 请求并返回响应记录器。
func doRequest(r *gin.Engine, method, target string, body []byte, headers map[string]string) *httptest.ResponseRecorder {
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
