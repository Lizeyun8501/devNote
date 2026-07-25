// DevNote 业务服务器 —— Go (Gin) 实现，处理知识图谱、标签、文件夹等业务逻辑
//
// 提供以下业务域的 RESTful API：
//  - metadata: 笔记元数据的 CRUD 和批量操作
//  - validate: 笔记/文件夹/标签/知识关系的校验规则管理
//  - tags: 层级标签的增删改查、合并/拆分、统计
//  - folders: 树形文件夹的 CRUD、移动/复制、路径解析
//  - knowledge: 知识图谱关系计算、关联推荐、最短路径、覆盖率分析

package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	sharedmw "github.com/devnote/shared/pkg/middleware"
	"github.com/devnote/shared/pkg/state"
	"github.com/devnote/business-server/internal/config"
	"github.com/devnote/business-server/internal/handler"
	"github.com/devnote/business-server/internal/middleware"
	"github.com/devnote/business-server/internal/service"
	"github.com/devnote/business-server/internal/storage"
	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

func main() {
	cfg := config.Load()

	// 集成 Sentry 崩溃报告 —— 借鉴 AppFlowy 的 Sentry 集成方案
	// 来源: https://github.com/AppFlowy-IO/AppFlowy
	// 检查 SENTRY_DSN 环境变量 —— 未设置时优雅降级
	sharedmw.InitSentry()

	logger := newLogger(cfg.LogLevel)
	defer logger.Sync()

	logger.Info("starting business-server",
		zap.String("port", cfg.Port),
		zap.String("db_path", cfg.DBPath),
	)

	// P0 修复（R1.12）: 使用 cfg.RedisURL 配置创建分布式状态存储
	// RedisURL 为空时使用 MemoryStore（单实例部署），非空时使用 RedisStore（多实例部署）
	stateStore, err := state.NewStore(cfg.RedisURL)
	if err != nil {
		log.Fatalf("failed to create state store: %v", err)
	}
	defer stateStore.Close()

	// Init SQLite store (sqlx + golang-migrate)
	store, err := storage.NewSQLiteStore(cfg.DBPath, cfg.MigrationsPath)
	if err != nil {
		log.Fatalf("failed to init sqlite: %v", err)
	}
	defer store.Close()

	// Init services (unified sqlx persistence layer)
	metadataSvc := service.NewMetadataService(store.DB)
	tagSvc := service.NewTagService(store.DB)
	folderSvc := service.NewFolderService(store.DB)

	validationCfg := service.ValidationConfig{
		MaxTagDepth:    cfg.MaxTagDepth,
		MaxFolderDepth: cfg.MaxFolderDepth,
		MaxNoteSize:    cfg.MaxNoteSize,
	}
	validationSvc := service.NewValidationService(store.DB, validationCfg)

	knowledgeCfg := service.KnowledgeConfig{
		PageRankDamping: cfg.PageRankDamping,
		PageRankIters:   cfg.PageRankIters,
	}
	knowledgeSvc := service.NewKnowledgeService(store.DB, knowledgeCfg)

	// Init handlers
	metadataHandler := handler.NewMetadataHandler(metadataSvc, logger)
	validationHandler := handler.NewValidationHandler(validationSvc, logger)
	tagHandler := handler.NewTagHandler(tagSvc, logger)
	folderHandler := handler.NewFolderHandler(folderSvc, logger)
	knowledgeHandler := handler.NewKnowledgeHandler(knowledgeSvc, logger)
	healthHandler := handler.NewHealthHandler(logger)

	// Gin engine
	r := gin.New()

	// Middleware
	// P1 架构修复 (3.6): Request ID 中间件，注入 X-Request-ID 便于跨服务链路追踪
	r.Use(middleware.RequestIDMiddleware())
	r.Use(sharedmw.SentryGin())
	r.Use(middleware.Recovery(logger))
	r.Use(middleware.LoggerMiddleware(logger))
	r.Use(middleware.CORSMiddleware(cfg.AllowedOrigins))
	// Phase 3-C: Prometheus 指标中间件，置于 CORS 之后、API 版本路由之前
	r.Use(middleware.MetricsMiddleware())
	// P1 安全修复: 添加安全响应头中间件（原完全缺失）
	r.Use(sharedmw.SecurityHeaders())
	// 修复(P0): 注册 API 版本控制中间件（原完全缺失）
	r.Use(sharedmw.APIVersionMiddleware(sharedmw.APIVersionConfig{
		Required:      false,
		LatestVersion: sharedmw.CurrentAPIVersion,
	}))
	rateLimitHandler, rateLimitStop := middleware.RateLimitMiddleware(cfg.RateLimit, stateStore)
	r.Use(rateLimitHandler)
	defer rateLimitStop()

	// Phase 3-C: Prometheus 指标暴露端点，供 Prometheus 抓取
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))

	// Health check
	r.GET("/api/v1/health", healthHandler.Check)

	// API v1
	api := r.Group("/api/v1")
	api.Use(middleware.JWTAuth(cfg.JWTSecret))

	// Metadata routes
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
	}

	// Validation routes
	{
		val := api.Group("/validate")
		val.GET("/note/:id", validationHandler.ValidateNote)
		val.GET("/folder/:id", validationHandler.ValidateFolder)
		val.GET("/tag/:id", validationHandler.ValidateTag)
		val.GET("/knowledge/:id", validationHandler.ValidateKnowledgeRelation)
		// Rule CRUD
		val.POST("/rules", validationHandler.CreateRule)
		val.GET("/rules", validationHandler.ListRules)
		val.PUT("/rules/:id", validationHandler.UpdateRule)
		val.DELETE("/rules/:id", validationHandler.DeleteRule)
		// Business rule CRUD
		val.POST("/business-rules", validationHandler.CreateBusinessRule)
		val.GET("/business-rules", validationHandler.ListBusinessRules)
		val.PUT("/business-rules/:id", validationHandler.UpdateBusinessRule)
		val.DELETE("/business-rules/:id", validationHandler.DeleteBusinessRule)
	}

	// Tag routes
	{
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
	}

	// Folder routes
	{
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
	}

	// Knowledge routes
	{
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

	addr := fmt.Sprintf(":%s", cfg.Port)

	// P0 修复 (R1.9): 使用 http.Server 包装 gin engine，支持优雅关闭
	// P2 修复: 设置读写/空闲超时，防止 Slowloris 慢速连接耗尽连接池/Goroutine 造成 DoS。
	// ReadHeaderTimeout 尤为关键 —— 它是防 Slowloris 的最有效手段（在读完请求头前就超时断开）。
	srv := &http.Server{
		Addr:              addr,
		Handler:           r,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		logger.Info("server listening", zap.String("addr", addr))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal("server error", zap.Error(err))
		}
	}()

	// Wait for shutdown signal
	sig := <-quit
	logger.Info("shutting down server", zap.String("signal", sig.String()))

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		logger.Fatal("server forced to shutdown", zap.Error(err))
	}

	logger.Info("server stopped gracefully")
}

func newLogger(level string) *zap.Logger {
	var lvl zapcore.Level
	switch level {
	case "debug":
		lvl = zapcore.DebugLevel
	case "warn":
		lvl = zapcore.WarnLevel
	case "error":
		lvl = zapcore.ErrorLevel
	default:
		lvl = zapcore.InfoLevel
	}

	cfg := zap.NewProductionConfig()
	cfg.Level = zap.NewAtomicLevelAt(lvl)
	cfg.EncoderConfig.TimeKey = "timestamp"
	cfg.EncoderConfig.EncodeTime = zapcore.ISO8601TimeEncoder

	logger, err := cfg.Build()
	if err != nil {
		log.Fatalf("failed to build logger: %v", err)
	}
	return logger
}