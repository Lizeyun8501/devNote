// 安全响应头中间件 —— 添加标准 HTTP 安全头
// P1 安全修复: 原实现完全缺失安全响应头，存在 XSS/clickjacking/MIME 嗅探风险
//
// 借鉴 OWASP Secure Headers Project
// 来源: https://owasp.org/www-project-secure-headers/
// 借鉴内容: 标准安全响应头配置

package middleware

import (
	"github.com/gin-gonic/gin"
)

// SecurityHeaders 添加标准安全响应头
func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		// 防止 MIME 类型嗅探
		c.Header("X-Content-Type-Options", "nosniff")

		// 防止点击劫持（clickjacking）
		c.Header("X-Frame-Options", "DENY")

		// 启用浏览器内置 XSS 过滤（旧版浏览器，新版已移除）
		c.Header("X-XSS-Protection", "1; mode=block")

		// 强制 HTTPS（1 年，包含子域名）
		c.Header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")

		// 内容安全策略：限制资源加载源
		// 允许同源 + 内联样式/脚本（API 服务通常不需要，但保留兼容性）
		c.Header("Content-Security-Policy", "default-src 'self'; frame-ancestors 'none'")

		// 控制引用信息，防止部分信息泄漏
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")

		// 禁用缓存（API 响应不应被缓存）
		c.Header("Cache-Control", "no-store, no-cache, must-revalidate, private")
		c.Header("Pragma", "no-cache")

		c.Next()
	}
}
