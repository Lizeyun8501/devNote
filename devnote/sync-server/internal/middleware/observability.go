package middleware

import (
	"fmt"
	"runtime/debug"
	"time"

	"github.com/devnote/sync-server/internal/observability"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"go.uber.org/zap"
)

// ObservabilityConfig holds configuration for the observability middleware.
type ObservabilityConfig struct {
	Logger  *zap.Logger
	Metrics *observability.Metrics
}

// Observability returns a Gin middleware that provides:
// - Request ID generation and injection
// - Structured request logging
// - Prometheus metrics collection
// - Panic recovery with stack trace logging
func Observability(cfg ObservabilityConfig) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Generate request ID
		requestID := c.GetHeader("X-Request-ID")
		if requestID == "" {
			requestID = uuid.New().String()
		}
		c.Set("request_id", requestID)
		c.Header("X-Request-ID", requestID)

		// Inject request ID into context
		ctx := observability.ContextWithRequestID(c.Request.Context(), requestID)
		c.Request = c.Request.WithContext(ctx)

		start := time.Now()

		// Track active connections
		if cfg.Metrics != nil {
			cfg.Metrics.ActiveConnections.Inc()
			defer cfg.Metrics.ActiveConnections.Dec()
		}

		// Panic recovery
		defer func() {
			if r := recover(); r != nil {
				stack := string(debug.Stack())
				if cfg.Logger != nil {
					cfg.Logger.Error("panic recovered",
						zap.String("request_id", requestID),
						zap.String("method", c.Request.Method),
						zap.String("path", c.Request.URL.Path),
						zap.Any("panic", r),
						zap.String("stack", stack),
					)
				}
				if cfg.Metrics != nil {
					cfg.Metrics.ErrorsTotal.WithLabelValues("panic").Inc()
				}
				c.AbortWithStatus(500)
			}
		}()

		// Process request
		c.Next()

		// Collect metrics
		duration := time.Since(start).Seconds()
		status := fmt.Sprintf("%d", c.Writer.Status())
		method := c.Request.Method
		path := c.FullPath()
		if path == "" {
			path = c.Request.URL.Path
		}

		if cfg.Metrics != nil {
			cfg.Metrics.RequestsTotal.WithLabelValues(method, path, status).Inc()
			cfg.Metrics.RequestDuration.WithLabelValues(method, path).Observe(duration)
		}

		// Structured logging
		if cfg.Logger != nil {
			fields := []zap.Field{
				zap.String("request_id", requestID),
				zap.String("method", method),
				zap.String("path", path),
				zap.Int("status", c.Writer.Status()),
				zap.Float64("duration", duration),
				zap.String("client_ip", c.ClientIP()),
				zap.Int("body_size", c.Writer.Size()),
			}

			if len(c.Errors) > 0 {
				fields = append(fields, zap.String("errors", c.Errors.String()))
				cfg.Logger.Warn("request completed with errors", fields...)
			} else if c.Writer.Status() >= 500 {
				cfg.Logger.Error("request completed with server error", fields...)
			} else if c.Writer.Status() >= 400 {
				cfg.Logger.Warn("request completed with client error", fields...)
			} else {
				cfg.Logger.Info("request completed", fields...)
			}
		}
	}
}

// GetRequestID retrieves the request ID from the Gin context.
func GetRequestID(c *gin.Context) string {
	if id, exists := c.Get("request_id"); exists {
		if s, ok := id.(string); ok {
			return s
		}
	}
	return ""
}

// LoggerFromContext returns a zap logger with request ID from Gin context.
func LoggerFromContext(c *gin.Context, logger *zap.Logger) *zap.Logger {
	reqID := GetRequestID(c)
	if reqID != "" {
		return logger.With(zap.String("request_id", reqID))
	}
	return logger
}

// LogSyncOperation logs a sync operation (push/pull/conflict) for observability.
func LogSyncOperation(c *gin.Context, logger *zap.Logger, metrics *observability.Metrics, operation, noteID, userID string) {
	if logger != nil {
		LoggerFromContext(c, logger).Info("sync operation",
			zap.String("operation", operation),
			zap.String("note_id", noteID),
			zap.String("user_id", userID),
		)
	}
	switch operation {
	case "push":
		if metrics != nil {
			metrics.SyncPushTotal.Inc()
		}
	case "pull":
		if metrics != nil {
			metrics.SyncPullTotal.Inc()
		}
	case "conflict":
		if metrics != nil {
			metrics.SyncConflictTotal.Inc()
		}
	}
}