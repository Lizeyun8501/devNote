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

	// P0 修复: 使用 cfg.RedisURL 而非硬编码空字符串，使配置生效
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
	logger.Info("server listening", zap.String("addr", addr))

	// P0 修复: 使用 http.Server + 信号监听实现优雅关闭
	// 原实现 r.Run() 无信号监听、无 Shutdown，log.Fatalf 调用 os.Exit(1)
	// 导致所有 defer 不执行，SQLite WAL 可能未正常 checkpoint
	srv := &http.Server{
		Addr:    addr,
		Handler: r,
	}

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("failed to start server: %v", err)
		}
	}()

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