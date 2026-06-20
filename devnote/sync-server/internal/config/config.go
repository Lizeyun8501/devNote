package config

import (
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
		// Only allow default in development
		jwtSecret = "devnote-dev-secret-key-change-me"
		log.Println("WARNING: Using default JWT_SECRET. Set JWT_SECRET env var for production.")
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
