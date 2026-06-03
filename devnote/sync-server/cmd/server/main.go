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

	// Initialize handlers
	authHandler := handler.NewAuthHandler(authService)
	srpAuthHandler := handler.NewSRPAuthHandler(authService)
	syncHandler := handler.NewSyncHandler(syncService)
	healthHandler := handler.NewHealthHandler()

	// Setup Gin router
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()

	// Global middleware
	r.Use(middleware.Observability(middleware.ObservabilityConfig{
		Logger:  logger,
		Metrics: metrics,
	}))
	r.Use(middleware.CORSMiddleware(cfg.AllowedOrigins))
	r.Use(middleware.RateLimitMiddleware(cfg.RateLimit))

	// Health check
	r.GET("/health", healthHandler.Check)

	// Prometheus metrics endpoint
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))

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
		}
	}

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