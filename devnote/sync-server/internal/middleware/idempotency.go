// 同步请求幂等键去重中间件 —— 防止客户端重试导致数据重复
// 借鉴 Stripe Idempotency-Key 机制
// 来源: https://stripe.com/docs/api/idempotent_requests
// 借鉴内容: 客户端生成 Idempotency-Key 头,服务端 24h 内对相同 key 返回相同响应
//
// 借鉴 AWS SQS MessageDeduplicationId 设计
// 来源: https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/FIFO-queues.html
// 借鉴内容: 同 key 在 TTL 窗口内只处理一次,处理完成后缓存结果
//
// P0 修复（单实例状态）: 幂等缓存从进程内 map 迁移到 StateStore，
// 支持多实例部署时跨进程共享缓存。

package middleware

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"time"

	"github.com/devnote/shared/pkg/state"
	"github.com/gin-gonic/gin"
)

// 幂等缓存相关常量
const (
	// idempotencyTTL 已完成响应的缓存保留时长
	idempotencyTTL = 24 * time.Hour
	// idempotencyLockTTL 占位锁的最大时长（防止处理崩溃后锁不释放）
	idempotencyLockTTL = 5 * time.Minute
)

// entryStatus 标识幂等条目的处理状态
type entryStatus int

const (
	// statusCompleted 表示请求已处理完成，缓存中存放的是最终响应
	statusCompleted entryStatus = iota
	// statusInProgress 表示请求正在处理中（占位标记），用于防止并发重复请求
	statusInProgress
)

// idempotencyEntryData 是幂等条目的可序列化形式，存储到 StateStore。
type idempotencyEntryData struct {
	Status       entryStatus `json:"status"`
	Hash         string      `json:"hash"`
	ResponseCode int         `json:"response_code"`
	ResponseBody string      `json:"response_body"`
}

// IdempotencyConfig 配置
type IdempotencyConfig struct {
	// Store 分布式状态存储，用于跨实例共享幂等缓存
	Store state.StateStore
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

// loadIdempotencyEntry 从 StateStore 加载并反序列化幂等条目。
// 不存在或反序列化失败时返回 false。
func loadIdempotencyEntry(store state.StateStore, ctx context.Context, key string) (idempotencyEntryData, bool) {
	raw, err := store.Get(ctx, key)
	if err != nil || raw == "" {
		return idempotencyEntryData{}, false
	}
	var e idempotencyEntryData
	if err := json.Unmarshal([]byte(raw), &e); err != nil {
		return idempotencyEntryData{}, false
	}
	return e, true
}

// IdempotencyMiddleware 幂等键中间件
//
// P0 修复: 缓存迁移到 StateStore。
// 并发安全：通过 IncrWithTTL 获取分布式锁实现"占位"，替代原内存 tryPutIfAbsent。
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

		ctx := c.Request.Context()
		dataKey := "idempotency:" + key
		lockKey := "idempotency:lock:" + key

		// 提前计算请求体哈希，命中与占位均需使用
		bodyHash := hashBody(c, cfg.MaxBodySize)

		// 缓存命中: 返回之前的结果(状态码 + body)，或拒绝并发中的重复请求
		if e, ok := loadIdempotencyEntry(cfg.Store, ctx, dataKey); ok {
			if e.Hash != "" && bodyHash != e.Hash {
				c.AbortWithStatusJSON(422, gin.H{
					"error": "Idempotency-Key reused with different request body",
				})
				return
			}
			if e.Status == statusInProgress {
				// 另一个相同 key 的请求正在处理中，拒绝并发重复
				c.AbortWithStatusJSON(http.StatusConflict, gin.H{
					"error": "duplicate request in progress",
				})
				return
			}
			c.Header("Idempotent-Replay", "true")
			c.Data(e.ResponseCode, "application/json", []byte(e.ResponseBody))
			c.Abort()
			return
		}

		// 缓存未命中: 通过 IncrWithTTL 原子占位，防止并发重复请求
		count, err := cfg.Store.IncrWithTTL(ctx, lockKey, idempotencyLockTTL)
		if err != nil {
			// 状态存储不可用时跳过幂等检查，直接处理请求
			c.Next()
			return
		}
		if count > 1 {
			// 在 get 与占位之间，另一个请求已占位
			c.AbortWithStatusJSON(http.StatusConflict, gin.H{
				"error": "duplicate request in progress",
			})
			return
		}

		// 获取锁后再次检查：防止与刚完成的请求竞态（另一请求在 get 与锁之间完成）
		if e, ok := loadIdempotencyEntry(cfg.Store, ctx, dataKey); ok && e.Status == statusCompleted {
			cfg.Store.Del(ctx, lockKey)
			if e.Hash != "" && bodyHash != e.Hash {
				c.AbortWithStatusJSON(422, gin.H{
					"error": "Idempotency-Key reused with different request body",
				})
				return
			}
			c.Header("Idempotent-Replay", "true")
			c.Data(e.ResponseCode, "application/json", []byte(e.ResponseBody))
			c.Abort()
			return
		}

		// 写入 in_progress 占位（带 bodyHash，供并发请求做哈希校验）
		placeholder := idempotencyEntryData{
			Status: statusInProgress,
			Hash:   bodyHash,
		}
		if data, err := json.Marshal(placeholder); err == nil {
			cfg.Store.Set(ctx, dataKey, string(data), idempotencyLockTTL)
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
			entry := idempotencyEntryData{
				Status:       statusCompleted,
				Hash:         bodyHash,
				ResponseCode: writer.Status(),
				ResponseBody: string(writer.body.bytes()),
			}
			if data, err := json.Marshal(entry); err == nil {
				cfg.Store.Set(ctx, dataKey, string(data), idempotencyTTL)
			}
		} else {
			// 非 2xx: 清理占位标记，允许客户端重试
			cfg.Store.Del(ctx, dataKey)
		}
		// 释放占位锁
		cfg.Store.Del(ctx, lockKey)
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
