// Package state 提供分布式状态存储抽象层
//
// 解决问题: sync-server 的 SRP 会话、Rate Limiter、Idempotency Cache、
// WebSocket Hub 均为进程内存状态，多实例部署时失效。
//
// 设计借鉴:
// - go-redis (github.com/redis/go-redis/v9): Redis 客户端接口
// - HashiCorp go-memdb: 内存 KV 存储
// - gorilla/sessions: Session 存储抽象
//
// 架构:
//   StateStore (接口)
//     ├── MemoryStore (内存实现，单实例部署，默认)
//     └── RedisStore  (Redis 实现，多实例部署，需配置 REDIS_URL)
//
// 使用方式:
//   store := state.NewStore(cfg.RedisURL)  // url 为空时用 MemoryStore
//   store.Set(ctx, "key", value, 5*time.Minute)
//   val, err := store.Get(ctx, "key")
//
// 迁移路径:
// 1. 当前: MemoryStore（单实例，与原行为一致）
// 2. 短期: 配置 REDIS_URL 后自动切换到 RedisStore
// 3. 长期: 所有进程内状态迁移到 StateStore
package state

import (
	"context"
	"sync"
	"time"
)

// StateStore 是分布式状态存储接口
//
// 借鉴 go-redis 的 Cmdable 接口设计，但简化为 KV + TTL 模式，
// 覆盖 SRP 会话、限流计数、幂等缓存等场景。
type StateStore interface {
	// Get 获取字符串值，不存在返回 ("", nil)
	Get(ctx context.Context, key string) (string, error)

	// Set 设置字符串值，带 TTL（0 表示永不过期）
	Set(ctx context.Context, key string, value string, ttl time.Duration) error

	// Del 删除 key，返回删除数量
	Del(ctx context.Context, keys ...string) (int64, error)

	// Exists 检查 key 是否存在
	Exists(ctx context.Context, key string) (bool, error)

	// Incr 原子递增，返回递增后的值
	// 用于限流计数器（rate limiter）
	Incr(ctx context.Context, key string) (int64, error)

	// IncrWithTTL 原子递增并设置 TTL（首次递增时设置）
	// 用于限流计数器 + 时间窗口自动过期
	IncrWithTTL(ctx context.Context, key string, ttl time.Duration) (int64, error)

	// Expire 为已存在的 key 设置过期时间
	Expire(ctx context.Context, key string, ttl time.Duration) error

	// Publish 发布消息到频道（用于 WebSocket 跨实例广播）
	// MemoryStore 实现为本地回调，RedisStore 实现为 Redis Pub/Sub
	Publish(ctx context.Context, channel string, message string) error

	// Subscribe 订阅频道消息
	// 返回 MessageChannel 和取消函数
	Subscribe(ctx context.Context, channels ...string) (<-chan Message, func(), error)

	// Close 关闭存储连接
	Close() error
}

// Message 是 Pub/Sub 消息
type Message struct {
	Channel string
	Payload string
}

// NewStore 根据配置创建状态存储
// redisURL 为空时使用 MemoryStore（单实例部署）
// redisURL 非空时使用 RedisStore（多实例部署）
func NewStore(redisURL string) (StateStore, error) {
	if redisURL == "" {
		return NewMemoryStore(), nil
	}
	return NewRedisStore(redisURL)
}

// ── MemoryStore 实现 ──────────────────────────────────────────

// memoryEntry 存储值和过期时间
type memoryEntry struct {
	value     string
	expiresAt time.Time // zero 表示永不过期
}

// isExpired 检查是否已过期
func (e *memoryEntry) isExpired() bool {
	return !e.expiresAt.IsZero() && time.Now().After(e.expiresAt)
}

// MemoryStore 是基于内存的 StateStore 实现
//
// 适用于单实例部署。使用 sync.RWMutex 保护并发访问。
// Pub/Sub 通过本地回调实现（无跨进程通信）。
type MemoryStore struct {
	mu         sync.RWMutex
	data       map[string]*memoryEntry
	subsMu     sync.RWMutex
	subscribers map[string][]chan Message
}

// NewMemoryStore 创建内存状态存储
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		data:        make(map[string]*memoryEntry),
		subscribers: make(map[string][]chan Message),
	}
}

func (s *MemoryStore) Get(ctx context.Context, key string) (string, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	entry, ok := s.data[key]
	if !ok || entry.isExpired() {
		return "", nil
	}
	return entry.value, nil
}

func (s *MemoryStore) Set(ctx context.Context, key string, value string, ttl time.Duration) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	entry := &memoryEntry{value: value}
	if ttl > 0 {
		entry.expiresAt = time.Now().Add(ttl)
	}
	s.data[key] = entry
	return nil
}

func (s *MemoryStore) Del(ctx context.Context, keys ...string) (int64, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var count int64
	for _, key := range keys {
		if _, ok := s.data[key]; ok {
			delete(s.data, key)
			count++
		}
	}
	return count, nil
}

func (s *MemoryStore) Exists(ctx context.Context, key string) (bool, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	entry, ok := s.data[key]
	return ok && !entry.isExpired(), nil
}

func (s *MemoryStore) Incr(ctx context.Context, key string) (int64, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	entry, ok := s.data[key]
	if !ok || entry.isExpired() {
		s.data[key] = &memoryEntry{value: "1"}
		return 1, nil
	}
	// 解析当前值并递增
	var current int64
	for _, c := range entry.value {
		if c < '0' || c > '9' {
			// 非数字，重置为 1
			current = 0
			break
		}
		current = current*10 + int64(c-'0')
	}
	current++
	entry.value = int64ToString(current)
	return current, nil
}

func (s *MemoryStore) IncrWithTTL(ctx context.Context, key string, ttl time.Duration) (int64, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	entry, ok := s.data[key]
	if !ok || entry.isExpired() {
		entry = &memoryEntry{
			value:     "1",
			expiresAt: time.Now().Add(ttl),
		}
		s.data[key] = entry
		return 1, nil
	}
	// 递增但不重置 TTL
	var current int64
	for _, c := range entry.value {
		if c < '0' || c > '9' {
			current = 0
			break
		}
		current = current*10 + int64(c-'0')
	}
	current++
	entry.value = int64ToString(current)
	return current, nil
}

func (s *MemoryStore) Expire(ctx context.Context, key string, ttl time.Duration) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	entry, ok := s.data[key]
	if !ok || entry.isExpired() {
		return nil // key 不存在，无操作
	}
	entry.expiresAt = time.Now().Add(ttl)
	return nil
}

func (s *MemoryStore) Publish(ctx context.Context, channel string, message string) error {
	s.subsMu.RLock()
	subs := s.subscribers[channel]
	s.subsMu.RUnlock()

	for _, sub := range subs {
		select {
		case sub <- Message{Channel: channel, Payload: message}:
		default:
			// 订阅者缓冲区满，跳过（避免阻塞发布者）
		}
	}
	return nil
}

func (s *MemoryStore) Subscribe(ctx context.Context, channels ...string) (<-chan Message, func(), error) {
	s.subsMu.Lock()
	defer s.subsMu.Unlock()

	ch := make(chan Message, 256)
	for _, channel := range channels {
		s.subscribers[channel] = append(s.subscribers[channel], ch)
	}

	// 返回取消函数
	cancel := func() {
		s.subsMu.Lock()
		defer s.subsMu.Unlock()
		for _, channel := range channels {
			subs := s.subscribers[channel]
			for i, sub := range subs {
				if sub == ch {
					s.subscribers[channel] = append(subs[:i], subs[i+1:]...)
					break
				}
			}
		}
		close(ch)
	}

	return ch, cancel, nil
}

func (s *MemoryStore) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.data = make(map[string]*memoryEntry)
	return nil
}

// int64ToString 将 int64 转为字符串（避免引入 strconv）
func int64ToString(n int64) string {
	if n == 0 {
		return "0"
	}
	negative := n < 0
	if negative {
		n = -n
	}
	var buf [20]byte
	pos := len(buf)
	for n > 0 {
		pos--
		buf[pos] = byte('0' + n%10)
		n /= 10
	}
	if negative {
		pos--
		buf[pos] = '-'
	}
	return string(buf[pos:])
}
