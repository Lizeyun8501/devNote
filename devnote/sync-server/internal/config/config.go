package config

import (
	"crypto/rand"
	"encoding/hex"
	"log"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Port           string
	HTTPPort       string
	DBPath         string
	JWTSecret      string
	AllowedOrigins []string
	S3Endpoint     string
	S3AccessKey    string
	S3SecretKey    string
	S3Bucket       string
	S3UseSSL       bool
	RateLimit      int
	TLSCertFile    string
	TLSKeyFile     string
	EnableTLS      bool
	AutoCert       bool
	HTTP2Enabled   bool
	LogLevel       string
	LogFormat      string
	EmailWebhookSecret string // 邮件 Webhook 验证密钥
	EmailDomain        string // 邮件域名，如 mail.devnote.app
}

func Load() *Config {
	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		if os.Getenv("GO_ENV") == "production" {
			log.Fatal("JWT_SECRET environment variable must be set in production")
		}
		// P1 修复 (SEC-06): 原实现使用固定默认密钥 "devnote-dev-secret-key-change-me"，
		// 可被预测伪造 token。现改为每次启动生成随机密钥（仅开发环境）。
		// 注意：随机密钥会导致重启后所有 token 失效，开发环境可接受。
		jwtSecret = generateRandomSecret(32)
		log.Println("WARNING: Generated random JWT_SECRET for development. "
			+ "Set JWT_SECRET env var for consistent sessions.")
	}

	// P1 修复 (SEC-06): 校验密钥长度至少 32 字节
	if len(jwtSecret) < 32 {
		if os.Getenv("GO_ENV") == "production" {
			log.Fatal("JWT_SECRET must be at least 32 bytes for security")
		}
		log.Printf("WARNING: JWT_SECRET is only %d bytes, recommend at least 32 bytes", len(jwtSecret))
	}

	allowedOrigins := parseEnvList("ALLOWED_ORIGINS", []string{"*"})

	return &Config{
		Port:           getEnv("PORT", "8080"),
		HTTPPort:       getEnv("HTTP_PORT", "8081"),
		DBPath:         getEnv("DB_PATH", "./data/sync.db"),
		JWTSecret:      jwtSecret,
		AllowedOrigins: allowedOrigins,
		S3Endpoint:     getEnv("S3_ENDPOINT", ""),
		S3AccessKey:    getEnv("S3_ACCESS_KEY", ""),
		S3SecretKey:    getEnv("S3_SECRET_KEY", ""),
		S3Bucket:       getEnv("S3_BUCKET", "devnote-sync"),
		S3UseSSL:       getEnvBool("S3_USE_SSL", false),
		RateLimit:      getEnvInt("RATE_LIMIT", 100),
		TLSCertFile:    getEnv("TLS_CERT_FILE", "./data/cert.pem"),
		TLSKeyFile:     getEnv("TLS_KEY_FILE", "./data/key.pem"),
		EnableTLS:      getEnvBool("ENABLE_TLS", false),
		AutoCert:       getEnvBool("AUTO_CERT", false),
		HTTP2Enabled:   getEnvBool("HTTP2_ENABLED", true),
		LogLevel:       getEnv("LOG_LEVEL", "info"),
		LogFormat:      getEnv("LOG_FORMAT", "json"),
		EmailWebhookSecret: getEnv("EMAIL_WEBHOOK_SECRET", ""),
		EmailDomain:        getEnv("EMAIL_DOMAIN", "mail.devnote.app"),
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getEnvBool(key string, fallback bool) bool {
	if v := os.Getenv(key); v != "" {
		b, _ := strconv.ParseBool(v)
		return b
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		i, _ := strconv.Atoi(v)
		return i
	}
	return fallback
}

func parseEnvList(key string, fallback []string) []string {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	var result []string
	for _, s := range strings.Split(v, ",") {
		trimmed := strings.TrimSpace(s)
		if trimmed != "" {
			result = append(result, trimmed)
		}
	}
	if len(result) == 0 {
		return fallback
	}
	return result
}

// generateRandomSecret 生成密码学安全的随机密钥（十六进制编码）
// P1 修复 (SEC-06): 替代固定默认密钥
func generateRandomSecret(byteLength int) string {
	b := make([]byte, byteLength)
	if _, err := rand.Read(b); err != nil {
		// rand.Read 失败极少见，失败时 panic 避免用弱密钥
		log.Fatalf("Failed to generate random secret: %v", err)
	}
	return hex.EncodeToString(b)
}
