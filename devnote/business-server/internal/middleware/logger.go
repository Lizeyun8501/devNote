package middleware

// 结构化日志中间件
// 借鉴: zerolog (https://github.com/rs/zerolog)
// 功能: 请求日志、响应时间、状态码、请求体大小

import (
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// LoggerMiddleware 创建基于 zap 的结构化请求日志中间件
// 记录每个请求的方法、路径、状态码、延迟、客户端 IP 和响应体大小
func LoggerMiddleware(logger *zap.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		rawQuery := c.Request.URL.RawQuery

		// 处理请求
		c.Next()

		// 计算请求延迟
		latency := time.Since(start)
		statusCode := c.Writer.Status()
		bodySize := c.Writer.Size()

		fields := []zap.Field{
			zap.String("method", c.Request.Method),
			zap.String("path", path),
			zap.Int("status", statusCode),
			zap.Duration("latency", latency),
			zap.String("client_ip", c.ClientIP()),
			zap.Int("body_size", bodySize),
		}
		if requestID, exists := c.Get("request_id"); exists {
			fields = append(fields, zap.String("request_id", requestID.(string)))
		}
		if rawQuery != "" {
			fields = append(fields, zap.String("query", rawQuery))
		}

		if statusCode >= 400 && statusCode < 500 {
			logger.Warn("client error", fields...)
		} else if statusCode >= 500 {
			logger.Error("server error", fields...)
		} else {
			logger.Info("request", fields...)
		}
	}
}