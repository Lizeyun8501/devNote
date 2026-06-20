package middleware

import (
	"strings"

	"github.com/gin-gonic/gin"
)

func CORSMiddleware(allowedOrigins []string) gin.HandlerFunc {
	isDev := len(allowedOrigins) == 1 && allowedOrigins[0] == "*"

	return func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")

		if isDev {
			c.Header("Access-Control-Allow-Origin", "*")
		} else if isExtensionOrigin(origin) {
			// 放行浏览器扩展（chrome-extension:// / moz-extension://）origin，
			// 以便 DevNote Web Clipper 扩展能够直接调用剪藏 API。
			c.Header("Access-Control-Allow-Origin", origin)
		} else {
			// Check if origin is in allowed list
			for _, allowed := range allowedOrigins {
				if allowed == origin {
					c.Header("Access-Control-Allow-Origin", origin)
					break
				}
			}
		}

		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Request-ID")
		c.Header("Access-Control-Allow-Credentials", "true")
		c.Header("Access-Control-Max-Age", "86400")

		// Handle OPTIONS preflight
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}

// isExtensionOrigin 判断 origin 是否来自浏览器扩展。
// Chrome/Edge 使用 chrome-extension://，Firefox 使用 moz-extension://。
func isExtensionOrigin(origin string) bool {
	return strings.HasPrefix(origin, "chrome-extension://") ||
		strings.HasPrefix(origin, "moz-extension://")
}

