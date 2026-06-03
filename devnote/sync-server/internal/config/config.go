package config

import (
	"os"
	"strconv"
)

type Config struct {
	Port         string
	HTTPPort     string
	DBPath       string
	JWTSecret    string
	S3Endpoint   string
	S3AccessKey  string
	S3SecretKey  string
	S3Bucket     string
	S3UseSSL     bool
	RateLimit    int
	TLSCertFile  string
	TLSKeyFile   string
	EnableTLS    bool
	AutoCert     bool
	HTTP2Enabled bool
	LogLevel     string
	LogFormat    string
}

func Load() *Config {
	return &Config{
		Port:         getEnv("PORT", "8080"),
		HTTPPort:     getEnv("HTTP_PORT", "8081"),
		DBPath:       getEnv("DB_PATH", "./data/sync.db"),
		JWTSecret:    getEnv("JWT_SECRET", "devnote-sync-secret-key"),
		S3Endpoint:   getEnv("S3_ENDPOINT", ""),
		S3AccessKey:  getEnv("S3_ACCESS_KEY", ""),
		S3SecretKey:  getEnv("S3_SECRET_KEY", ""),
		S3Bucket:     getEnv("S3_BUCKET", "devnote-sync"),
		S3UseSSL:     getEnvBool("S3_USE_SSL", false),
		RateLimit:    getEnvInt("RATE_LIMIT", 100),
		TLSCertFile:  getEnv("TLS_CERT_FILE", "./data/cert.pem"),
		TLSKeyFile:   getEnv("TLS_KEY_FILE", "./data/key.pem"),
		EnableTLS:    getEnvBool("ENABLE_TLS", false),
		AutoCert:     getEnvBool("AUTO_CERT", false),
		HTTP2Enabled: getEnvBool("HTTP2_ENABLED", true),
		LogLevel:     getEnv("LOG_LEVEL", "info"),
		LogFormat:    getEnv("LOG_FORMAT", "json"),
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
