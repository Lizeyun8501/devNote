package main

import (
	"log"

	"github.com/devnote/sync-server/internal/config"
	"github.com/devnote/sync-server/internal/handler"
	"github.com/devnote/sync-server/internal/middleware"
	"github.com/devnote/sync-server/internal/service"
	"github.com/devnote/sync-server/internal/storage"
	"github.com/gin-gonic/gin"
)

func main() {
	cfg := config.Load()

	sqliteStore, err := storage.NewSQLiteStorage(cfg.DBPath)
	if err != nil {
		log.Fatalf("failed to init sqlite: %v", err)
	}
	defer sqliteStore.Close()

	s3Store, err := storage.NewS3Storage(cfg)
	if err != nil {
		log.Fatalf("failed to init s3: %v", err)
	}

	authService := service.NewAuthService(sqliteStore.DB, cfg)
	syncService := service.NewSyncService(sqliteStore.DB, s3Store)

	authHandler := handler.NewAuthHandler(authService)
	syncHandler := handler.NewSyncHandler(syncService)
	healthHandler := handler.NewHealthHandler()

	r := gin.Default()

	r.Use(middleware.CORS())
	r.Use(middleware.RateLimit(cfg.RateLimit))

	r.GET("/health", healthHandler.Check)

	api := r.Group("/api/v1")
	{
		auth := api.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
		}

		sync := api.Group("/sync")
		sync.Use(middleware.JWTAuth(authService))
		{
			sync.POST("/push", syncHandler.Push)
			sync.POST("/pull", syncHandler.Pull)
			sync.GET("/status", syncHandler.Status)
			sync.POST("/resolve-conflict", syncHandler.ResolveConflict)
		}
	}

	log.Printf("starting server on :%s", cfg.Port)
	if err := r.Run(":" + cfg.Port); err != nil {
		log.Fatalf("failed to start server: %v", err)
	}
}
