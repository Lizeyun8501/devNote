// API 版本控制中间件 —— 借鉴 REST API 最佳实践
// 借鉴 Kubernetes 的 API 版本协商机制
// 来源: https://kubernetes.io/docs/concepts/overview/kubernetes-api/#api-versioning
// 借鉴内容: 通过请求头 X-API-Version 协商版本,默认 v1,
//         不兼容时返回 400 + Supported-versions 响应头
//
// 借鉴 Stripe 的 API 版本回退策略
// 来源: https://stripe.com/docs/api/versioning
// 借鉴内容: 客户端可通过 Stripe-Version 头指定 API 版本,服务端提供向后兼容

package middleware

import (
	"net/http"
	"regexp"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

const (
	// CurrentAPIVersion 当前 API 主版本号
	CurrentAPIVersion = "v1"
	// MinSupportedVersion 最低向后兼容版本
	MinSupportedVersion = "v1"
	// APIVersionHeader 客户端指定的 API 版本请求头
	APIVersionHeader = "X-API-Version"
	// SupportedVersionsHeader 响应中告知客户端支持的版本
	SupportedVersionsHeader = "X-Supported-Versions"
)

// versionRegex 校验形如 v1, v2, v2.1 的版本号
var versionRegex = regexp.MustCompile(`^v\d+(\.\d+)?$`)

// APIVersionConfig 中间件配置
type APIVersionConfig struct {
	// Required: 设为 true 时拒绝未指定版本号的请求
	Required bool
	// LatestVersion: 用于 DefaultVersion
	LatestVersion string
}

// APIVersionMiddleware API 版本协商中间件
func APIVersionMiddleware(cfg APIVersionConfig) gin.HandlerFunc {
	if cfg.LatestVersion == "" {
		cfg.LatestVersion = CurrentAPIVersion
	}
	return func(c *gin.Context) {
		// 响应头始终告知客户端支持的版本范围
		c.Header(SupportedVersionsHeader, MinSupportedVersion+"-"+cfg.LatestVersion)

		requested := c.GetHeader(APIVersionHeader)
		if requested == "" {
			if cfg.Required {
				c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{
					"error":              "API version required",
					"required_header":    APIVersionHeader,
					"supported_versions": []string{MinSupportedVersion, cfg.LatestVersion},
				})
				return
			}
			// 未指定则使用当前主版本
			c.Set("api_version", cfg.LatestVersion)
			c.Next()
			return
		}

		// 标准化: "1" -> "v1", "v2.1" -> "v2.1"
		if !strings.HasPrefix(requested, "v") {
			requested = "v" + requested
		}

		if !versionRegex.MatchString(requested) {
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{
				"error":   "Invalid API version format",
				"got":     requested,
				"pattern": "^v\\d+(\\.\\d+)?$",
			})
			return
		}

		// 提取主版本号 (v2.1 -> v2)
		major := strings.SplitN(requested, ".", 2)[0]
		majorNum, err := strconv.Atoi(strings.TrimPrefix(major, "v"))
		if err != nil {
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": "Invalid API version"})
			return
		}
		minNum, _ := strconv.Atoi(strings.TrimPrefix(MinSupportedVersion, "v"))
		maxNum, _ := strconv.Atoi(strings.TrimPrefix(cfg.LatestVersion, "v"))

		if majorNum < minNum || majorNum > maxNum {
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{
				"error":              "Unsupported API version",
				"requested":          requested,
				"supported_versions": []string{MinSupportedVersion, cfg.LatestVersion},
			})
			return
		}

		c.Set("api_version", requested)
		c.Next()
	}
}

// GetAPIVersion 从 context 读取协商后的 API 版本(供 handler 使用)
func GetAPIVersion(c *gin.Context) string {
	if v, ok := c.Get("api_version"); ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return CurrentAPIVersion
}
