package storage

import (
	"context"
	"errors"
	"io"
	"log"
	"net/http"

	"github.com/devnote/sync-server/internal/config"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

// ErrS3NotConfigured 表示 S3 存储未配置（S3Endpoint 为空）
// P3 修复 (P3-8): 原实现 client 为 nil 时静默返回 nil，调用方无法区分"对象不存在"和"S3 未配置"
var ErrS3NotConfigured = errors.New("S3 storage is not configured (S3_ENDPOINT is empty)")

type S3Storage struct {
	client    *minio.Client
	bucket    string
	transport http.RoundTripper
}

func NewS3Storage(cfg *config.Config) (*S3Storage, error) {
	if cfg.S3Endpoint == "" {
		return &S3Storage{bucket: cfg.S3Bucket}, nil
	}

	transport := http.DefaultTransport.(*http.Transport).Clone()
	client, err := minio.New(cfg.S3Endpoint, &minio.Options{
		Creds:     credentials.NewStaticV4(cfg.S3AccessKey, cfg.S3SecretKey, ""),
		Secure:    cfg.S3UseSSL,
		Transport: transport,
	})
	if err != nil {
		return nil, err
	}

	ctx := context.Background()
	exists, err := client.BucketExists(ctx, cfg.S3Bucket)
	if err != nil {
		return nil, err
	}
	if !exists {
		if err := client.MakeBucket(ctx, cfg.S3Bucket, minio.MakeBucketOptions{}); err != nil {
			return nil, err
		}
		log.Printf("created bucket: %s", cfg.S3Bucket)
	}

	return &S3Storage{client: client, bucket: cfg.S3Bucket, transport: transport}, nil
}

// Close 释放底层 HTTP 连接池资源。
func (s *S3Storage) Close() error {
	if s.transport != nil {
		if tr, ok := s.transport.(*http.Transport); ok {
			tr.CloseIdleConnections()
		}
	}
	return nil
}

// P3 修复 (P3-8): client 为 nil 时返回明确错误，让调用方决定降级策略
func (s *S3Storage) Upload(ctx context.Context, key string, reader io.Reader, size int64, contentType string) error {
	if s.client == nil {
		return ErrS3NotConfigured
	}
	_, err := s.client.PutObject(ctx, s.bucket, key, reader, size, minio.PutObjectOptions{
		ContentType: contentType,
	})
	return err
}

func (s *S3Storage) Download(ctx context.Context, key string) (*minio.Object, error) {
	if s.client == nil {
		return nil, ErrS3NotConfigured
	}
	return s.client.GetObject(ctx, s.bucket, key, minio.GetObjectOptions{})
}

func (s *S3Storage) Delete(ctx context.Context, key string) error {
	if s.client == nil {
		return ErrS3NotConfigured
	}
	return s.client.RemoveObject(ctx, s.bucket, key, minio.RemoveObjectOptions{})
}
