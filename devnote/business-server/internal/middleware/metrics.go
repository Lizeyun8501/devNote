// Prometheus 指标中间件 —— Phase 3-C 可观测性 Part 1
//
// 收集 HTTP 请求指标，供 Prometheus 抓取：
//   - http_requests_total: 请求总数 (counter, labels: method, path, status)
//   - http_request_duration_seconds: 请求延迟分布 (histogram, labels: method, path)
//
// 借鉴 prometheus/client_golang 的标准中间件模式:
//   https://github.com/prometheus/client_golang/blob/main/prometheus/promhttp/instrument_server.go
//
// 路径处理: 使用 gin 的路由模板 (c.FullPath()) 而非实际 URL，
// 避免 /api/v1/folders/:id 这类带路径参数的请求造成指标基数爆炸。

package middleware

import (
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
)

// 默认延迟分桶，覆盖典型 HTTP 请求耗时范围 (1ms ~ 10s)
var defaultBuckets = []float64{
	0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10,
}

// 指标单例 —— 全进程共享同一组 collector，避免重复注册
var (
	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "HTTP 请求总数，按方法、路径、状态码分类",
		},
		[]string{"method", "path", "status"},
	)

	httpRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP 请求延迟分布（秒）",
			Buckets: defaultBuckets,
		},
		[]string{"method", "path"},
	)
)

func init() {
	// 注册默认 collector 到默认注册表
	prometheus.MustRegister(httpRequestsTotal, httpRequestDuration)
}

// MetricsMiddleware 收集 HTTP 请求指标（请求数、延迟、状态码分布）
// 借鉴 prometheus/client_golang 的标准中间件模式
func MetricsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()

		// 先执行后续 handler，拿到最终状态码
		c.Next()

		// 使用路由模板而非实际 URL，避免路径参数造成指标基数爆炸
		path := c.FullPath()
		if path == "" {
			// 未匹配到路由的请求 (例如 404) 用 actual path 兜底
			path = "unmatched"
		}
		method := c.Request.Method
		status := strconv.Itoa(c.Writer.Status())

		// 记录延迟直方图
		httpRequestDuration.WithLabelValues(method, path).Observe(time.Since(start).Seconds())

		// 记录请求计数
		httpRequestsTotal.WithLabelValues(method, path, status).Inc()
	}
}
