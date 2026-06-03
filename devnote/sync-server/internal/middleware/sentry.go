// 集成 Sentry 崩溃报告 —— 借鉴 AppFlowy 的 Sentry 集成方案
// 来源: https://github.com/AppFlowy-IO/AppFlowy

package middleware

import (
	"log"
	"os"
	"runtime/debug"
	"time"

	"github.com/getsentry/sentry-go"
	sentrygin "github.com/getsentry/sentry-go/gin"
	"github.com/gin-gonic/gin"
)

// InitSentry 初始化 Sentry —— 检查 SENTRY_DSN 环境变量，未设置时优雅降级
//
// 借鉴 AppFlowy 的 sentry-contrib-native 集成方式
// 来源: https://github.com/AppFlowy-IO/AppFlowy
func InitSentry() {
	dsn := os.Getenv("SENTRY_DSN")
	if dsn == "" {
		log.Println("[Sentry] SENTRY_DSN not set — Sentry is disabled (graceful fallback)")
		return
	}

	environment := os.Getenv("SENTRY_ENVIRONMENT")
	if environment == "" {
		environment = "production"
	}

	err := sentry.Init(sentry.ClientOptions{
		// TODO: 替换为实际 Sentry DSN
		Dsn:         dsn,
		Environment: environment,
		// 设置采样率
		TracesSampleRate: 1.0,
		// 过滤 PII（个人身份信息）
		BeforeSend: func(event *sentry.Event, hint *sentry.EventHint) *sentry.Event {
			// 移除请求中的敏感信息
			if event.Request != nil && event.Request.URL != "" {
				// 过滤 /auth/ 路径的请求数据
				// 保留请求但清空可能包含密码的 body
				event.Request.Data = ""
			}
			return event
		},
	})
	if err != nil {
		log.Printf("[Sentry] Failed to initialize: %v", err)
		return
	}

	log.Printf("[Sentry] Initialized — environment: %s", environment)
}

// SentryRecovery 是一个 Gin 中间件，捕获 panic 并上报到 Sentry
//
// 借鉴 AppFlowy 的 sentry-contrib-native 集成，FFI panic 时自动上报 Sentry
// 来源: https://github.com/AppFlowy-IO/AppFlowy
func SentryRecovery() gin.HandlerFunc {
	return func(c *gin.Context) {
		defer func() {
			if r := recover(); r != nil {
				// 上报到 Sentry
				if hub := sentry.GetHubFromContext(c.Request.Context()); hub != nil {
					hub.RecoverWithContext(c.Request.Context(), r)
				} else {
					sentry.CurrentHub().RecoverWithContext(c.Request.Context(), r)
				}
				// 等待事件上报完成
				sentry.Flush(2 * time.Second)
				// 重新 panic 让 Gin 的 recovery 中间件处理
				panic(r)
			}
		}()
		c.Next()
	}
}

// SentryPanicRecovery 是一个独立的 recovery 中间件，捕获 panic、上报 Sentry 并返回 500
// 替代默认的 Gin recovery 中间件
//
// 借鉴 AppFlowy 的 sentry-contrib-native 集成，FFI panic 时自动上报 Sentry
// 来源: https://github.com/AppFlowy-IO/AppFlowy
func SentryPanicRecovery() gin.HandlerFunc {
	return func(c *gin.Context) {
		defer func() {
			if r := recover(); r != nil {
				// 上报到 Sentry
				if hub := sentry.GetHubFromContext(c.Request.Context()); hub != nil {
					hub.Recover(r)
				} else {
					sentry.CurrentHub().Recover(r)
				}
				sentry.Flush(2 * time.Second)

				stack := string(debug.Stack())
				log.Printf("[Sentry] Panic recovered: %v\n%s", r, stack)

				c.AbortWithStatusJSON(500, gin.H{
					"code":    500,
					"message": "internal server error",
				})
			}
		}()
		c.Next()
	}
}

// SentryGin 返回 Sentry 的 Gin 集成中间件
// 该中间件将 Sentry Hub 注入到 gin.Context 中
func SentryGin() gin.HandlerFunc {
	return sentrygin.New(sentrygin.Options{
		Repanic:         false,
		WaitForDelivery: false,
	})
}