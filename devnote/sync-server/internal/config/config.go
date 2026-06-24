package config

import (
	"crypto/rand"
	"encoding/hex"
	"log"
	"strings"

	"github.com/spf13/viper"
)

type Config struct {
	Port               string
	HTTPPort           string
	DBPath             string
	MigrationsPath     string
	JWTSecret          string
	AllowedOrigins     []string
	S3Endpoint         string
	S3AccessKey        string
	S3SecretKey        string
	S3Bucket           string
	S3UseSSL           bool
	RateLimit          int
	TLSCertFile        string
	TLSKeyFile         string
	EnableTLS          bool
	AutoCert           bool
	HTTP2Enabled       bool
	LogLevel           string
	LogFormat          string
	EmailWebhookSecret string // 邮件 Webhook 验证密钥
	EmailDomain        string // 邮件域名，如 mail.devnote.app
}

// Load 通过 Viper 加载配置，优先级：环境变量 > 配置文件 > 默认值。
//
// 配置来源（P2-7 统一配置管理）：
//   - 配置文件: config.yaml（搜索路径: . / ./config / /etc/devnote/sync-server）
//   - 环境变量: 保持原有变量名向后兼容（PORT / DB_PATH / JWT_SECRET 等）
//   - 默认值: 与原实现一致
func Load() *Config {
	v := viper.New()

	// 默认值
	v.SetDefault("port", "8080")
	v.SetDefault("http_port", "8081")
	v.SetDefault("db_path", "./data/sync.db")
	v.SetDefault("migrations_path", "./migrations")
	v.SetDefault("allowed_origins", "*")
	v.SetDefault("s3_endpoint", "")
	v.SetDefault("s3_access_key", "")
	v.SetDefault("s3_secret_key", "")
	v.SetDefault("s3_bucket", "devnote-sync")
	v.SetDefault("s3_use_ssl", false)
	v.SetDefault("rate_limit", 100)
	v.SetDefault("tls_cert_file", "./data/cert.pem")
	v.SetDefault("tls_key_file", "./data/key.pem")
	v.SetDefault("enable_tls", false)
	v.SetDefault("auto_cert", false)
	v.SetDefault("http2_enabled", true)
	v.SetDefault("log_level", "info")
	v.SetDefault("log_format", "json")
	v.SetDefault("email_webhook_secret", "")
	v.SetDefault("email_domain", "mail.devnote.app")

	// 配置文件搜索路径
	v.SetConfigName("config")
	v.SetConfigType("yaml")
	v.AddConfigPath(".")
	v.AddConfigPath("./config")
	v.AddConfigPath("/etc/devnote/sync-server")
	if err := v.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			log.Printf("WARNING: 读取配置文件失败: %v", err)
		}
	}

	// 环境变量绑定（保持原有变量名，向后兼容）
	v.BindEnv("port", "PORT")
	v.BindEnv("http_port", "HTTP_PORT")
	v.BindEnv("db_path", "DB_PATH")
	v.BindEnv("migrations_path", "MIGRATIONS_PATH")
	v.BindEnv("jwt_secret", "JWT_SECRET")
	v.BindEnv("allowed_origins", "ALLOWED_ORIGINS")
	v.BindEnv("s3_endpoint", "S3_ENDPOINT")
	v.BindEnv("s3_access_key", "S3_ACCESS_KEY")
	v.BindEnv("s3_secret_key", "S3_SECRET_KEY")
	v.BindEnv("s3_bucket", "S3_BUCKET")
	v.BindEnv("s3_use_ssl", "S3_USE_SSL")
	v.BindEnv("rate_limit", "RATE_LIMIT")
	v.BindEnv("tls_cert_file", "TLS_CERT_FILE")
	v.BindEnv("tls_key_file", "TLS_KEY_FILE")
	v.BindEnv("enable_tls", "ENABLE_TLS")
	v.BindEnv("auto_cert", "AUTO_CERT")
	v.BindEnv("http2_enabled", "HTTP2_ENABLED")
	v.BindEnv("log_level", "LOG_LEVEL")
	v.BindEnv("log_format", "LOG_FORMAT")
	v.BindEnv("email_webhook_secret", "EMAIL_WEBHOOK_SECRET")
	v.BindEnv("email_domain", "EMAIL_DOMAIN")
	v.BindEnv("go_env", "GO_ENV")

	// JWT 密钥处理
	jwtSecret := v.GetString("jwt_secret")
	if jwtSecret == "" {
		if v.GetString("go_env") == "production" {
			log.Fatal("JWT_SECRET must be set in production (env or config.yaml)")
		}
		// P1 修复 (SEC-06): 原实现使用固定默认密钥 "devnote-dev-secret-key-change-me"，
		// 可被预测伪造 token。现改为每次启动生成随机密钥（仅开发环境）。
		jwtSecret = generateRandomSecret(32)
		log.Println("WARNING: Generated random JWT_SECRET for development. " +
			"Set JWT_SECRET env var or config.yaml for consistent sessions.")
	}
	if len(jwtSecret) < 32 {
		if v.GetString("go_env") == "production" {
			log.Fatal("JWT_SECRET must be at least 32 bytes for security")
		}
		log.Printf("WARNING: JWT_SECRET is only %d bytes, recommend at least 32 bytes", len(jwtSecret))
	}

	return &Config{
		Port:               v.GetString("port"),
		HTTPPort:           v.GetString("http_port"),
		DBPath:             v.GetString("db_path"),
		MigrationsPath:     v.GetString("migrations_path"),
		JWTSecret:          jwtSecret,
		AllowedOrigins:     parseOrigins(v.GetString("allowed_origins")),
		S3Endpoint:         v.GetString("s3_endpoint"),
		S3AccessKey:        v.GetString("s3_access_key"),
		S3SecretKey:        v.GetString("s3_secret_key"),
		S3Bucket:           v.GetString("s3_bucket"),
		S3UseSSL:           v.GetBool("s3_use_ssl"),
		RateLimit:          v.GetInt("rate_limit"),
		TLSCertFile:        v.GetString("tls_cert_file"),
		TLSKeyFile:         v.GetString("tls_key_file"),
		EnableTLS:          v.GetBool("enable_tls"),
		AutoCert:           v.GetBool("auto_cert"),
		HTTP2Enabled:       v.GetBool("http2_enabled"),
		LogLevel:           v.GetString("log_level"),
		LogFormat:          v.GetString("log_format"),
		EmailWebhookSecret: v.GetString("email_webhook_secret"),
		EmailDomain:        v.GetString("email_domain"),
	}
}

// parseOrigins 解析 CORS 允许的来源列表。
// 支持逗号分隔字符串（env var）和 YAML 列表两种格式。
func parseOrigins(raw string) []string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return []string{"*"}
	}
	var result []string
	for _, s := range strings.Split(raw, ",") {
		s = strings.TrimSpace(s)
		if s != "" {
			result = append(result, s)
		}
	}
	if len(result) == 0 {
		return []string{"*"}
	}
	return result
}

// generateRandomSecret 生成密码学安全的随机密钥（十六进制编码）
// P1 修复 (SEC-06): 替代固定默认密钥
func generateRandomSecret(byteLength int) string {
	b := make([]byte, byteLength)
	if _, err := rand.Read(b); err != nil {
		log.Fatalf("Failed to generate random secret: %v", err)
	}
	return hex.EncodeToString(b)
}
