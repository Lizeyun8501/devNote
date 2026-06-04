// Syncthing 流量控制适配器
//
// 借鉴的开源项目:
// - Syncthing (https://github.com/syncthing/syncthing): 开源 P2P 文件同步工具
//   借鉴其流量控制和速率限制机制，通过信号量和令牌桶算法实现并发控制
//
// 实现说明: 提供同步请求的流量控制，限制单个设备的同步带宽，
// 避免大量同步时占用过多网络资源。
package service

import (
	"context"
	"sync"
	"time"
)

// SyncthingAdapter 是 Syncthing 流量控制适配器
// 借鉴 Syncthing 的速率限制配置，通过信号量控制并发同步数和带宽
type SyncthingAdapter struct {
	maxBandwidthBPS    int64 // 最大带宽（字节/秒）
	maxConcurrentSyncs int   // 最大并发同步数

	semaphore chan struct{} // 信号量，控制最大并发数

	mu         sync.Mutex
	bandwidth  int64       // 当前已用带宽
	lastReset  time.Time   // 上次重置带宽统计的时间
}

// NewSyncthingAdapter 创建一个新的 Syncthing 流量控制适配器
// maxBandwidthBPS: 最大带宽，单位为字节/秒
// maxConcurrent: 最大并发同步数
func NewSyncthingAdapter(maxBandwidthBPS int64, maxConcurrent int) *SyncthingAdapter {
	return &SyncthingAdapter{
		maxBandwidthBPS:    maxBandwidthBPS,
		maxConcurrentSyncs: maxConcurrent,
		semaphore:          make(chan struct{}, maxConcurrent),
		lastReset:          time.Now(),
	}
}

// AcquireSemaphore 获取同步令牌，阻塞直到有空闲的同步槽位
// 借鉴 Syncthing 的并发控制机制，使用带缓冲的 channel 作为信号量
func (a *SyncthingAdapter) AcquireSemaphore() {
	a.semaphore <- struct{}{}
}

// ReleaseSemaphore 释放同步令牌，允许其他同步请求进入
func (a *SyncthingAdapter) ReleaseSemaphore() {
	<-a.semaphore
}

// TryAcquireSemaphore 尝试获取同步令牌，超时则返回 false
// 避免无限期阻塞，借鉴 Syncthing 的超时重试机制
func (a *SyncthingAdapter) TryAcquireSemaphore(ctx context.Context) bool {
	select {
	case a.semaphore <- struct{}{}:
		return true
	case <-ctx.Done():
		return false
	}
}

// CheckBandwidth 检查当前带宽使用情况，返回是否超过限制
// 借鉴 Syncthing 的带宽统计机制，定期重置统计窗口
func (a *SyncthingAdapter) CheckBandwidth() bool {
	a.mu.Lock()
	defer a.mu.Unlock()

	// 每分钟重置一次带宽统计窗口
	if time.Since(a.lastReset) > time.Minute {
		a.bandwidth = 0
		a.lastReset = time.Now()
	}

	return a.bandwidth >= a.maxBandwidthBPS
}

// AddBandwidthUsage 增加带宽使用量
func (a *SyncthingAdapter) AddBandwidthUsage(bytes int64) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.bandwidth += bytes
}

// WaitForBandwidth 等待直到带宽低于限制
// 使用定时检查的方式，避免忙等待
func (a *SyncthingAdapter) WaitForBandwidth(ctx context.Context) error {
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
			if !a.CheckBandwidth() {
				return nil
			}
		}
	}
}

// GetSemaphoreCount 获取当前正在进行的同步数量
func (a *SyncthingAdapter) GetSemaphoreCount() int {
	return len(a.semaphore)
}

// GetMaxConcurrent 获取最大并发数
func (a *SyncthingAdapter) GetMaxConcurrent() int {
	return a.maxConcurrentSyncs
}

// GetMaxBandwidth 获取最大带宽限制（字节/秒）
func (a *SyncthingAdapter) GetMaxBandwidth() int64 {
	return a.maxBandwidthBPS
}
