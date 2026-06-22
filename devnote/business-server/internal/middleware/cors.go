package middleware

import (
	"github.com/gin-gonic/gin"
)

// CORSMiddleware 处理跨域请求
//
// P1 修复 (SEC-05): 原实现开发模式同时设置 Allow-Origin: * 与 Allow-Credentials: true，
// 浏览器规范明确禁止此组合，credentials 请求会被拒绝。
// 现改为：开发模式也回显具体 Origin 而非 *，与 sync-server 的 cors.go 做法对齐。
func CORSMiddleware(allowedOrigins []string) gin.HandlerFunc {
	isDev := len(allowedOrigins) == 1 && allowedOrigins[0] == "*"

	return func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")
		originAllowed := false

		if isDev {
			// P1 修复: 开发模式回显具体 Origin，而非通配符 *
			// 这样 Allow-Credentials: true 才能正常工作
			if origin != "" {
				c.Header("Access-Control-Allow-Origin", origin)
				originAllowed = true
			}
		} else {
			// 生产模式：检查 origin 是否在白名单中
			for _, allowed := range allowedOrigins {
				if allowed == origin {
					c.Header("Access-Control-Allow-Origin", origin)
					originAllowed = true
					break
				}
			}
		}

		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Request-ID")
		// P1 修复: 仅在 origin 被允许时设置 Allow-Credentials
		if originAllowed {
			c.Header("Access-Control-Allow-Credentials", "true")
		}
		c.Header("Access-Control-Max-Age", "86400")

		// Handle OPTIONS preflight
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}
