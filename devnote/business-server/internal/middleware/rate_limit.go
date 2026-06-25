package middleware

// 速率限制中间件
// 借鉴: uber-go/ratelimit (https://github.com/uber-go/ratelimit)
// 原实现使用 golang.org/x/time/rate 令牌桶算法（进程内）
//
// P0 修复（单实例状态）: 限流计数器从进程内 map 迁移到 StateStore，
// 使用固定窗口计数器（IncrWithTTL）支持多实例部署。
// MemoryStore 在单实例时行为与原实现等价。

import (
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/devnote/shared/pkg/state"
	"github.com/gin-gonic/gin"
)

// rateLimitWindow 限流时间窗口（1 分钟）
const rateLimitWindow = 1 * time.Minute

// RateLimitMiddleware 创建基于固定窗口计数器的速率限制中间件
//
// 使用 StateStore 的 IncrWithTTL 原子递增并设置 TTL，支持多实例共享计数。
// 针对不同端点使用差异化限制：认证端点 5/min，业务端点 30/min，健康检查 120/min。
//
// 返回 (gin.HandlerFunc, func())，第二个返回值是停止函数（保留以兼容原签名，
// 迁移到 StateStore 后无需后台清理协程，故为空操作）。
func RateLimitMiddleware(requestsPerSecond int, store state.StateStore) (gin.HandlerFunc, func()) {
	if requestsPerSecond <= 0 {
		requestsPerSecond = 100 // 默认: 100 req/s
	}
	// 默认每分钟限额 = 每秒限额 * 60（固定窗口换算）
	defaultLimit := int64(requestsPerSecond) * 60

	handler := func(c *gin.Context) {
		// 使用 method + path + IP 作为限流键，实现按端点粒度限流
		path := c.FullPath()
		key := fmt.Sprintf("ratelimit:%s:%s:%s", c.Request.Method, path, c.ClientIP())

		// 不同端点使用差异化限流策略
		var limit int64 = defaultLimit
		if strings.Contains(path, "/auth/login") || strings.Contains(path, "/auth/register") {
			limit = 5 // 认证端点: 5 req/min
		} else if strings.Contains(path, "/api") {
			limit = 30 // 业务 API: 30 req/min
		} else if strings.Contains(path, "/health") {
			limit = 120 // 健康检查: 120 req/min
		}

		// IncrWithTTL 原子递增：首次递增时设置 1 分钟 TTL（时间窗口自动过期）
		count, err := store.IncrWithTTL(c.Request.Context(), key, rateLimitWindow)
		if err != nil {
			// 状态存储不可用时放行请求，避免限流故障导致服务不可用
			c.Next()
			return
		}
		if count > limit {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error":   "rate limit exceeded",
				"message": "请求过于频繁，请稍后重试",
			})
			c.Abort()
			return
		}
		c.Next()
	}

	// 兼容原签名的停止函数（迁移到 StateStore 后无需后台清理，故为空操作）
	stop := func() {}

	return handler, stop
}
