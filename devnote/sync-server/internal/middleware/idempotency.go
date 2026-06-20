// 同步请求幂等键去重中间件 —— 防止客户端重试导致数据重复
// 借鉴 Stripe Idempotency-Key 机制
// 来源: https://stripe.com/docs/api/idempotent_requests
// 借鉴内容: 客户端生成 Idempotency-Key 头,服务端 24h 内对相同 key 返回相同响应
//
// 借鉴 AWS SQS MessageDeduplicationId 设计
// 来源: https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/FIFO-queues.html
// 借鉴内容: 同 key 在 TTL 窗口内只处理一次,处理完成后缓存结果

package middleware

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// IdempotencyCache 内存 LRU 缓存
// 生产环境建议替换为 Redis 以支持多实例共享
type IdempotencyCache struct {
	mu      sync.RWMutex
	entries map[string]idempotencyEntry
	ttl     time.Duration
	maxSize int
}

// entryStatus 标识幂等条目的处理状态
type entryStatus int

const (
	// statusCompleted 表示请求已处理完成，缓存中存放的是最终响应
	statusCompleted entryStatus = iota
	// statusInProgress 表示请求正在处理中（占位标记），用于防止并发重复请求
	statusInProgress
)

type idempotencyEntry struct {
	status       entryStatus
	hash         string
	responseCode int
	responseBody []byte
	expiresAt    time.Time
}

// NewIdempotencyCache 创建幂等键缓存
func NewIdempotencyCache(ttl time.Duration, maxSize int) *IdempotencyCache {
	c := &IdempotencyCache{
		entries: make(map[string]idempotencyEntry),
		ttl:     ttl,
		maxSize: maxSize,
	}
	go c.gc()
	return c
}

func (c *IdempotencyCache) gc() {
	ticker := time.NewTicker(c.ttl / 2)
	defer ticker.Stop()
	for range ticker.C {
		c.mu.Lock()
		now := time.Now()
		for k, v := range c.entries {
			if now.After(v.expiresAt) {
				delete(c.entries, k)
			}
		}
		c.mu.Unlock()
	}
}

func (c *IdempotencyCache) get(key string) (idempotencyEntry, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	e, ok := c.entries[key]
	if !ok || time.Now().After(e.expiresAt) {
		return idempotencyEntry{}, false
	}
	return e, true
}

func (c *IdempotencyCache) put(key string, e idempotencyEntry) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if len(c.entries) >= c.maxSize {
		now := time.Now()
		for k, v := range c.entries {
			if now.After(v.expiresAt) {
				delete(c.entries, k)
			}
		}
	}
	e.expiresAt = time.Now().Add(c.ttl)
	c.entries[key] = e
}

// tryPutIfAbsent 原子地写入条目：仅当 key 不存在（或已过期）时才写入。
// 返回 true 表示占位成功，false 表示已有未过期的条目存在（被其他请求占用）。
// 该方法用于消除 get 与 put 之间的 TOCTOU 竞态窗口。
func (c *IdempotencyCache) tryPutIfAbsent(key string, e idempotencyEntry) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if existing, ok := c.entries[key]; ok && !time.Now().After(existing.expiresAt) {
		return false
	}
	if len(c.entries) >= c.maxSize {
		now := time.Now()
		for k, v := range c.entries {
			if now.After(v.expiresAt) {
				delete(c.entries, k)
			}
		}
	}
	e.expiresAt = time.Now().Add(c.ttl)
	c.entries[key] = e
	return true
}

// remove 删除指定 key 的条目，用于处理失败请求后清理占位标记以便重试。
func (c *IdempotencyCache) remove(key string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.entries, key)
}

// IdempotencyConfig 配置
type IdempotencyConfig struct {
	Cache *IdempotencyCache
	// RequiredMethods: 仅对这些 HTTP 方法做幂等检查(默认 POST/PUT/PATCH/DELETE)
	RequiredMethods []string
	// HeaderName 幂等键请求头
	HeaderName string
	// MaxBodySize 用于哈希计算的最大 body 字节数
	MaxBodySize int64
}

var defaultIdempotencyMethods = map[string]bool{
	"POST":   true,
	"PUT":    true,
	"PATCH":  true,
	"DELETE": true,
}

// IdempotencyMiddleware 幂等键中间件
func IdempotencyMiddleware(cfg IdempotencyConfig) gin.HandlerFunc {
	if cfg.HeaderName == "" {
		cfg.HeaderName = "Idempotency-Key"
	}
	if cfg.MaxBodySize == 0 {
		cfg.MaxBodySize = 1 << 20 // 1 MiB
	}
	methods := defaultIdempotencyMethods
	if cfg.RequiredMethods != nil {
		methods = map[string]bool{}
		for _, m := range cfg.RequiredMethods {
			methods[m] = true
		}
	}

	return func(c *gin.Context) {
		if !methods[c.Request.Method] {
			c.Next()
			return
		}

		key := c.GetHeader(cfg.HeaderName)
		if key == "" {
			c.Next()
			return
		}
		if len(key) > 256 {
			c.AbortWithStatusJSON(400, gin.H{"error": "Idempotency-Key too long (max 256)"})
			return
		}

		// 提前计算请求体哈希，命中与占位均需使用
		bodyHash := hashBody(c, cfg.MaxBodySize)

		// 缓存命中: 返回之前的结果(状态码 + body)，或拒绝并发中的重复请求
		if e, ok := cfg.Cache.get(key); ok {
			if e.hash != "" && bodyHash != e.hash {
				c.AbortWithStatusJSON(422, gin.H{
					"error": "Idempotency-Key reused with different request body",
				})
				return
			}
			if e.status == statusInProgress {
				// 另一个相同 key 的请求正在处理中，拒绝并发重复
				c.AbortWithStatusJSON(http.StatusConflict, gin.H{
					"error": "duplicate request in progress",
				})
				return
			}
			c.Header("Idempotent-Replay", "true")
			c.Data(e.responseCode, "application/json", e.responseBody)
			c.Abort()
			return
		}

		// 缓存未命中: 原子占位，防止 get 与 put 之间的 TOCTOU 竞态
		placeholder := idempotencyEntry{
			status: statusInProgress,
			hash:   bodyHash,
		}
		if !cfg.Cache.tryPutIfAbsent(key, placeholder) {
			// 在 get 与 tryPutIfAbsent 之间，另一个请求已占位
			c.AbortWithStatusJSON(http.StatusConflict, gin.H{
				"error": "duplicate request in progress",
			})
			return
		}

		// 占位成功: 注册 hook 在 handler 完成后捕获响应
		writer := &idempotentResponseWriter{
			ResponseWriter: c.Writer,
			body:           &buffer{},
		}
		c.Writer = writer

		c.Next()

		// 仅缓存 2xx 响应,避免错误结果被固化 24h
		if writer.Status() >= 200 && writer.Status() < 300 {
			cfg.Cache.put(key, idempotencyEntry{
				status:       statusCompleted,
				hash:         bodyHash,
				responseCode: writer.Status(),
				responseBody: writer.body.bytes(),
			})
		} else {
			// 非 2xx: 清理占位标记，允许客户端重试
			cfg.Cache.remove(key)
		}
	}
}

func hashBody(c *gin.Context, maxSize int64) string {
	if c.Request.ContentLength > maxSize {
		return ""
	}
	body, err := readAndRestoreBody(c)
	if err != nil {
		return ""
	}
	h := sha256.Sum256(body)
	return hex.EncodeToString(h[:])
}

// readAndRestoreBody 读取请求体并重置到 Body 以便后续 handler 可继续读取
func readAndRestoreBody(c *gin.Context) ([]byte, error) {
	if c.Request.Body == nil {
		return nil, nil
	}
	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		return nil, err
	}
	c.Request.Body = io.NopCloser(bytes.NewReader(body))
	return body, nil
}

// buffer 简单字节缓冲
type buffer struct {
	data []byte
}

func (b *buffer) Write(p []byte) (int, error) {
	b.data = append(b.data, p...)
	return len(p), nil
}

func (b *buffer) bytes() []byte {
	return b.data
}

// idempotentResponseWriter 包装 gin.ResponseWriter 捕获输出
type idempotentResponseWriter struct {
	gin.ResponseWriter
	body *buffer
}

func (w *idempotentResponseWriter) Write(p []byte) (int, error) {
	w.body.Write(p)
	return w.ResponseWriter.Write(p)
}

func (w *idempotentResponseWriter) WriteString(s string) (int, error) {
	return w.Write([]byte(s))
}
