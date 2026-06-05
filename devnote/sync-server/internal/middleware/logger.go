package middleware

// 结构化日志中间件
// 借鉴: zerolog (https://github.com/rs/zerolog)
// 功能: 请求日志、响应时间、状态码、请求体大小

import (
	"time"

	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog"
)

// LoggerMiddleware 创建基于 zerolog 的结构化请求日志中间件
// 记录每个请求的方法、路径、状态码、延迟、客户端 IP 和响应体大小
// 借鉴: zerolog 的零分配日志设计，性能优于 zap
func LoggerMiddleware(logger zerolog.Logger) gin.HandlerFunc {
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

		// 构建结构化日志事件
		logEvent := logger.Info().
			Str("method", c.Request.Method).
			Str("path", path).
			Int("status", statusCode).
			Dur("latency", latency).
			Str("client_ip", c.ClientIP()).
			Int("body_size", bodySize)

		if rawQuery != "" {
			logEvent = logEvent.Str("query", rawQuery)
		}

		// 错误请求使用 Warn 级别
		if statusCode >= 400 && statusCode < 500 {
			logger.Warn().
				Str("method", c.Request.Method).
				Str("path", path).
				Int("status", statusCode).
				Dur("latency", latency).
				Str("client_ip", c.ClientIP()).
				Msg("client error")
		} else if statusCode >= 500 {
			logger.Error().
				Str("method", c.Request.Method).
				Str("path", path).
				Int("status", statusCode).
				Dur("latency", latency).
				Str("client_ip", c.ClientIP()).
				Msg("server error")
		} else {
			logEvent.Msg("request")
		}
	}
}