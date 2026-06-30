// Package middleware provides shared middleware for DevNote Go services.
//
// P0 架构修复 (P1): API 版本协商中间件
// 客户端应在请求中携带 Accept-Version 头，服务端验证版本兼容性。
// 若客户端版本不兼容，返回 426 Upgrade Required 并提示客户端升级。
package middleware

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// CurrentAPIVersion 当前服务端 API 版本号
const CurrentAPIVersion = 1

// APIVersionConfig 配置 API 版本协商参数
type APIVersionConfig struct {
	// Required 是否强制要求 Accept-Version 头（严格模式）
	Required bool
	// LatestVersion 当前服务端 API 版本号
	LatestVersion int
}

// DefaultAPIVersionConfig 默认 API 版本协商配置
func DefaultAPIVersionConfig() APIVersionConfig {
	return APIVersionConfig{
		Required:      false,
		LatestVersion: CurrentAPIVersion,
	}
}

// APIVersionMiddleware 验证客户端 API 版本兼容性。
//
// 客户端请求应携带 Accept-Version 头（整数），例如：
//
//	Accept-Version: 1
//
// 若 Required=true，请求头缺失时返回 400 Bad Request。
// 若 Required=false，请求头缺失时放行并记录警告。
//
// 响应头始终返回 Api-Version: LatestVersion。
func APIVersionMiddleware(cfg APIVersionConfig) gin.HandlerFunc {
	return func(c *gin.Context) {
		// 响应头始终返回当前版本
		c.Header("Api-Version", strconv.Itoa(cfg.LatestVersion))

		versionHeader := c.GetHeader("Accept-Version")
		if versionHeader == "" {
			if cfg.Required {
				c.JSON(http.StatusBadRequest, gin.H{
					"error":          "missing Accept-Version header",
					"current_version": cfg.LatestVersion,
				})
				c.Abort()
				return
			}
			c.Next()
			return
		}

		clientVersion, err := strconv.Atoi(strings.TrimSpace(versionHeader))
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{
				"error":          "invalid Accept-Version header: must be an integer",
				"current_version": cfg.LatestVersion,
			})
			c.Abort()
			return
		}

		if clientVersion > cfg.LatestVersion {
			c.JSON(http.StatusUpgradeRequired, gin.H{
				"error":          "client version too new, server may need upgrade",
				"client_version": clientVersion,
				"server_version": cfg.LatestVersion,
			})
			c.Abort()
			return
		}

		c.Next()
	}
}