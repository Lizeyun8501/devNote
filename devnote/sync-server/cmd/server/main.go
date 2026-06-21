// DevNote 同步服务器 —— Go (Gin) 实现，处理多设备同步请求
// 借鉴 Joplin Sync Server 的架构设计和 API 结构
//
// 借鉴 Joplin Sync Server 的架构设计
// 来源: https://github.com/laurent22/joplin
// 借鉴内容: push/pull 增量同步 API、JWT 鉴权、delta sync 协议、冲突解决接口

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

	"github.com/devnote/sync-server/internal/cert"
	"github.com/devnote/sync-server/internal/config"
	"github.com/devnote/sync-server/internal/handler"
	"github.com/devnote/sync-server/internal/middleware"
	"github.com/devnote/sync-server/internal/observability"
	"github.com/devnote/sync-server/internal/service"
	"github.com/devnote/sync-server/internal/storage"
	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.uber.org/zap"
	"golang.org/x/net/http2"
	"golang.org/x/net/http2/h2c"
)

func main() {
	cfg := config.Load()

	// 集成 Sentry 崩溃报告 —— 借鉴 AppFlowy 的 Sentry 集成方案
	// 来源: https://github.com/AppFlowy-IO/AppFlowy
	// 检查 SENTRY_DSN 环境变量 —— 未设置时优雅降级
	middleware.InitSentry()

	// Initialize structured logger
	logger, err := observability.NewLogger(cfg.LogLevel, cfg.LogFormat)
	if err != nil {
		log.Fatalf("failed to initialize logger: %v", err)
	}
	defer logger.Sync()

	logger.Info("starting DevNote sync-server",
		zap.String("port", cfg.Port),
		zap.Bool("tls_enabled", cfg.EnableTLS),
		zap.Bool("http2_enabled", cfg.HTTP2Enabled),
		zap.Bool("auto_cert", cfg.AutoCert),
	)

	// Initialize metrics
	metrics := observability.NewMetrics()

	// Initialize storage
	sqliteStore, err := storage.NewSQLiteStorage(cfg.DBPath)
	if err != nil {
		logger.Fatal("failed to init sqlite", zap.Error(err))
	}
	defer sqliteStore.Close()

	s3Store, err := storage.NewS3Storage(cfg)
	if err != nil {
		logger.Fatal("failed to init s3", zap.Error(err))
	}

	// Initialize services
	authService := service.NewAuthService(sqliteStore.DB, cfg)
	syncService := service.NewSyncService(sqliteStore.DB, s3Store)
	shareService := service.NewShareService(sqliteStore.DB)
	emailService := service.NewEmailService(sqliteStore.DB, syncService, cfg.EmailDomain)

	// Initialize handlers
	authHandler := handler.NewAuthHandler(authService)
	srpAuthHandler := handler.NewSRPAuthHandler(authService)
	syncHandler := handler.NewSyncHandler(syncService)
	healthHandler := handler.NewHealthHandler()
	realtimeHandler := handler.NewRealtimeHandler(authService)
	clipperHandler := handler.NewClipperHandler(syncService)
	shareHandler := handler.NewShareHandler(shareService)
	emailHandler := handler.NewEmailHandler(emailService, cfg.EmailWebhookSecret)

	// Setup Gin router
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()

	// Global middleware
	r.Use(middleware.SentryGin())
	r.Use(middleware.Observability(middleware.ObservabilityConfig{
		Logger:  logger,
		Metrics: metrics,
	}))
	r.Use(middleware.CORSMiddleware(cfg.AllowedOrigins))
	// 修复(P0): 注册 API 版本控制中间件（原已实现但未挂载，为死代码）
	r.Use(middleware.APIVersionMiddleware(middleware.APIVersionConfig{
		Required:      false,
		LatestVersion: middleware.CurrentAPIVersion,
	}))
	rateLimitHandler, rateLimitStop := middleware.RateLimitMiddleware(cfg.RateLimit)
	r.Use(rateLimitHandler)
	defer rateLimitStop()

	// Health check
	r.GET("/health", healthHandler.Check)

	// Prometheus metrics endpoint
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))

	// 实时协作 WebSocket
	// 注册在根级别 /realtime，与客户端 wss://sync.devnote.app/realtime 对齐。
	// 不经过 JWTAuth 中间件：WebSocket 升级时无法使用标准 Bearer header，
	// 改为在 handler 内部从 query param 校验 JWT。
	r.GET("/realtime", realtimeHandler.Connect)

	// API v1 routes
	api := r.Group("/api/v1")
	{
		// Auth routes
		auth := api.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
			auth.POST("/refresh", authHandler.RefreshToken)
			auth.POST("/logout", authHandler.Logout)

			// SRP authentication routes
			srp := auth.Group("/srp")
			{
				srp.POST("/register", srpAuthHandler.Register)
				srp.POST("/init", srpAuthHandler.Init)
				srp.POST("/verify", srpAuthHandler.Verify)
			}
		}

		// Sync routes (protected)
		sync := api.Group("/sync")
		sync.Use(middleware.JWTAuth(authService))
		{
			sync.POST("/push", syncHandler.Push)
			sync.POST("/pull", syncHandler.Pull)
			sync.GET("/status", syncHandler.Status)
			sync.POST("/resolve-conflict", syncHandler.ResolveConflict)

			// 版本历史
			sync.GET("/notes/:noteId/history", syncHandler.GetNoteHistory)
			sync.GET("/notes/:noteId/versions/:version", syncHandler.GetNoteVersion)
		}

		// Clipper API (protected) —— 网页剪藏扩展入口
		notes := api.Group("/notes")
		notes.Use(middleware.JWTAuth(authService))
		{
			notes.POST("/clip", clipperHandler.Clip)
		}

		// 分享管理 API（需认证）—— 公开分享/发布笔记，对标 Obsidian Publish
		shares := api.Group("/shares")
		shares.Use(middleware.JWTAuth(authService))
		{
			shares.POST("", shareHandler.CreateShare)
			shares.GET("", shareHandler.ListShares)
			shares.DELETE("/:shareId", shareHandler.DeleteShare)
		}

		// 邮件转笔记管理 API（需认证）—— 获取/重新生成专属邮箱别名
		email := api.Group("/email")
		email.Use(middleware.JWTAuth(authService))
		{
			email.GET("/alias", emailHandler.GetUserAlias)
			email.POST("/alias/regenerate", emailHandler.RegenerateAlias)
		}
	}

	// 公开访问分享的笔记（无需认证）
	r.GET("/s/:token", shareHandler.GetSharedNote)

	// 邮件 Webhook（无需认证，通过签名验证）—— 接收 SendGrid/Mailgun/SES 等邮件入站
	r.POST("/webhooks/email", emailHandler.IncomingEmailWebhook)

	// Handle TLS / AutoCert
	if cfg.EnableTLS && cfg.AutoCert {
		logger.Info("generating self-signed certificate",
			zap.String("cert_file", cfg.TLSCertFile),
			zap.String("key_file", cfg.TLSKeyFile),
		)
		if err := cert.GenerateSelfSignedCert(cfg.TLSCertFile, cfg.TLSKeyFile); err != nil {
			logger.Fatal("failed to generate self-signed cert", zap.Error(err))
		}
	}

	// Setup HTTP server with optional TLS/HTTP2
	var srv *http.Server
	if cfg.EnableTLS {
		srv = &http.Server{
			Addr:    fmt.Sprintf(":%s", cfg.Port),
			Handler: r,
		}

		// Enable HTTP/2
		if cfg.HTTP2Enabled {
			if err := http2.ConfigureServer(srv, nil); err != nil {
				logger.Fatal("failed to configure HTTP/2", zap.Error(err))
			}
			logger.Info("HTTP/2 enabled")
		}

		// Start HTTP-to-HTTPS redirect server
		go func() {
			redirectServer := &http.Server{
				Addr: fmt.Sprintf(":%s", cfg.HTTPPort),
				Handler: h2c.NewHandler(
					http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
						target := fmt.Sprintf("https://%s%s", r.Host, r.URL.RequestURI())
						if cfg.Port != "443" {
							target = fmt.Sprintf("https://%s:%s%s", r.Host, cfg.Port, r.URL.RequestURI())
						}
						http.Redirect(w, r, target, http.StatusMovedPermanently)
					}),
					&http2.Server{},
				),
			}
			logger.Info("starting HTTP redirect server", zap.String("addr", redirectServer.Addr))
			if err := redirectServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				logger.Error("HTTP redirect server error", zap.Error(err))
			}
		}()
	} else {
		srv = &http.Server{
			Addr:    fmt.Sprintf(":%s", cfg.Port),
			Handler: r,
		}
		// Enable h2c (HTTP/2 cleartext) if HTTP2 is enabled without TLS
		if cfg.HTTP2Enabled {
			srv.Handler = h2c.NewHandler(r, &http2.Server{})
			logger.Info("HTTP/2 cleartext (h2c) enabled")
		}
	}

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		if cfg.EnableTLS {
			logger.Info("starting HTTPS server",
				zap.String("addr", srv.Addr),
				zap.String("cert", cfg.TLSCertFile),
				zap.String("key", cfg.TLSKeyFile),
			)
			if err := srv.ListenAndServeTLS(cfg.TLSCertFile, cfg.TLSKeyFile); err != nil && err != http.ErrServerClosed {
				logger.Fatal("HTTPS server error", zap.Error(err))
			}
		} else {
			logger.Info("starting HTTP server", zap.String("addr", srv.Addr))
			if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				logger.Fatal("HTTP server error", zap.Error(err))
			}
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