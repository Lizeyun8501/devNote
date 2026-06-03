package middleware

import (
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/time/rate"
)

type visitor struct {
	limiter  *rate.Limiter
	lastSeen time.Time
}

func RateLimitMiddleware(requestsPerMinute int) gin.HandlerFunc {
	var mu sync.Mutex
	visitors := make(map[string]*visitor)

	// Cleanup goroutine
	go func() {
		for {
			time.Sleep(time.Minute)
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
		// Use method + path + IP as key for per-endpoint rate limiting
		key := fmt.Sprintf("%s:%s:%s", c.Request.Method, c.FullPath(), c.ClientIP())

		mu.Lock()
		v, exists := visitors[key]
		if !exists {
			// Different limits for different endpoints
			limit := requestsPerMinute
			path := c.FullPath()
			if strings.Contains(path, "/auth/login") || strings.Contains(path, "/auth/register") {
				limit = 5 // Stricter for auth endpoints
			} else if strings.Contains(path, "/sync/push") || strings.Contains(path, "/sync/pull") {
				limit = 30 // More generous for sync
			} else if strings.Contains(path, "/health") {
				limit = 120 // Health checks can be frequent
			}
			v = &visitor{limiter: rate.NewLimiter(rate.Limit(limit)/60, limit), lastSeen: time.Now()}
			visitors[key] = v
		}
		v.lastSeen = time.Now()
		mu.Unlock()

		if !v.limiter.Allow() {
			c.JSON(http.StatusTooManyRequests, gin.H{"error": "rate limit exceeded"})
			c.Abort()
			return
		}
		c.Next()
	}
}
