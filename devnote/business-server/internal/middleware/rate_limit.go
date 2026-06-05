package middleware

// 速率限制中间件
// 借鉴: uber-go/ratelimit (https://github.com/uber-go/ratelimit)
// 使用: golang.org/x/time/rate 令牌桶算法
// 默认: 100 req/s, 突发容量 200

import (
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/time/rate"
)

// visitor 记录每个请求端的限流器和最后访问时间
type visitor struct {
	limiter  *rate.Limiter
	lastSeen time.Time
}

// RateLimitMiddleware 创建基于令牌桶算法的速率限制中间件
// 默认每秒 100 请求，突发容量 200
// 针对不同端点使用差异化限制：认证端点 5/min，业务端点 30/min，健康检查 120/min
func RateLimitMiddleware(requestsPerSecond int) gin.HandlerFunc {
	if requestsPerSecond <= 0 {
		requestsPerSecond = 100 // 默认: 100 req/s
	}
	burst := requestsPerSecond * 2 // 突发容量: 200

	var mu sync.Mutex
	visitors := make(map[string]*visitor)

	// 后台清理协程：每 3 分钟清理超过 3 分钟未活跃的访问者
	go func() {
		for {
			time.Sleep(3 * time.Minute)
			mu.Lock()
			for ip, v := range visitors {
				if time.Since(v.lastSeen) > 3*time.Minute {
					delete(visitors, ip)
				}
			}
			mu.Unlock()
		}
	}()

	return func(c *gin.Context) {
		// 使用 method + path + IP 作为限流键，实现按端点粒度限流
		key := fmt.Sprintf("%s:%s:%s", c.Request.Method, c.FullPath(), c.ClientIP())

		mu.Lock()
		v, exists := visitors[key]
		if !exists {
			// 不同端点使用差异化限流策略
			limit := rate.Limit(requestsPerSecond)
			path := c.FullPath()
			if strings.Contains(path, "/auth/login") || strings.Contains(path, "/auth/register") {
				limit = rate.Limit(5) / 60 // 认证端点: 5 req/min
			} else if strings.Contains(path, "/api") {
				limit = rate.Limit(30) / 60 // 业务 API: 30 req/min
			} else if strings.Contains(path, "/health") {
				limit = rate.Limit(120) / 60 // 健康检查: 120 req/min
			}
			v = &visitor{
				limiter:  rate.NewLimiter(limit, burst),
				lastSeen: time.Now(),
			}
			visitors[key] = v
		}
		v.lastSeen = time.Now()
		mu.Unlock()

		// 令牌桶算法判断：Allow() 尝试消费一个令牌
		if !v.limiter.Allow() {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error":   "rate limit exceeded",
				"message": "请求过于频繁，请稍后重试",
			})
			c.Abort()
			return
		}
		c.Next()
	}
}