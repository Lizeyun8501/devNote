// RedisStore 是基于 Redis 的 StateStore 实现
//
// 适用于多实例部署。使用 go-redis 客户端。
// 借鉴: github.com/redis/go-redis/v9
//
// 功能:
// - KV 读写（GET/SET）
// - 原子递增（INCR + EXPIRE）
// - Pub/Sub（用于 WebSocket 跨实例广播）
package state

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
)

// RedisStore 是基于 Redis 的 StateStore 实现
type RedisStore struct {
	client *redis.Client
}

// NewRedisStore 创建 Redis 状态存储
// redisURL 格式: redis://[:password@]host[:port][/db]
func NewRedisStore(redisURL string) (*RedisStore, error) {
	opts, err := redis.ParseURL(redisURL)
	if err != nil {
		return nil, fmt.Errorf("invalid redis URL: %w", err)
	}

	client := redis.NewClient(opts)

	// 测试连接
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := client.Ping(ctx).Err(); err != nil {
		client.Close()
		return nil, fmt.Errorf("redis ping failed: %w", err)
	}

	return &RedisStore{client: client}, nil
}

func (s *RedisStore) Get(ctx context.Context, key string) (string, error) {
	val, err := s.client.Get(ctx, key).Result()
	if err == redis.Nil {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return val, nil
}

func (s *RedisStore) Set(ctx context.Context, key string, value string, ttl time.Duration) error {
	return s.client.Set(ctx, key, value, ttl).Err()
}

func (s *RedisStore) Del(ctx context.Context, keys ...string) (int64, error) {
	if len(keys) == 0 {
		return 0, nil
	}
	return s.client.Del(ctx, keys...).Result()
}

func (s *RedisStore) Exists(ctx context.Context, key string) (bool, error) {
	n, err := s.client.Exists(ctx, key).Result()
	return n > 0, err
}

func (s *RedisStore) Incr(ctx context.Context, key string) (int64, error) {
	return s.client.Incr(ctx, key).Result()
}

func (s *RedisStore) IncrWithTTL(ctx context.Context, key string, ttl time.Duration) (int64, error) {
	// 使用 Lua 脚本保证 INCR + EXPIRE 原子性
	// 仅在 key 新建时设置 TTL（避免每次递增都重置 TTL）
	script := redis.NewScript(`
		local current = redis.call('INCR', KEYS[1])
		if current == 1 then
			redis.call('EXPIRE', KEYS[1], ARGV[1])
		end
		return current
	`)
	return script.Run(ctx, s.client, []string{key}, int(ttl.Seconds())).Int64()
}

func (s *RedisStore) Expire(ctx context.Context, key string, ttl time.Duration) error {
	return s.client.Expire(ctx, key, ttl).Err()
}

func (s *RedisStore) Publish(ctx context.Context, channel string, message string) error {
	return s.client.Publish(ctx, channel, message).Err()
}

func (s *RedisStore) Subscribe(ctx context.Context, channels ...string) (<-chan Message, func(), error) {
	pubsub := s.client.Subscribe(ctx, channels...)

	// 获取消息通道
	redisCh := pubsub.Channel()

	// 转换为统一的 Message 类型
	outCh := make(chan Message, 256)
	var wg sync.WaitGroup
	wg.Add(1)

	go func() {
		defer wg.Done()
		defer close(outCh)
		for msg := range redisCh {
			select {
			case outCh <- Message{Channel: msg.Channel, Payload: msg.Payload}:
			case <-ctx.Done():
				return
			}
		}
	}()

	cancel := func() {
		pubsub.Close()
		wg.Wait()
	}

	return outCh, cancel, nil
}

func (s *RedisStore) Close() error {
	return s.client.Close()
}
