package config

import (
	"crypto/rand"
	"encoding/hex"
	"log"
	"os"
	"strconv"
	"strings"
)

// Config holds all configuration for the business server.
type Config struct {
	Port            string
	DBPath          string
	MigrationsPath  string
	JWTSecret       string
	AllowedOrigins  []string
	LogLevel        string
	MaxTagDepth     int
	MaxFolderDepth  int
	MaxNoteSize     int
	PageRankDamping float64
	PageRankIters   int
	RateLimit       int
}

// Load reads configuration from environment variables with sensible defaults.
//
// P1 修复 (SEC-06): business-server 应使用独立的 JWT_SECRET，不与 sync-server 共用。
// 原实现两服务器共用同一密钥，任一泄露即可伪造另一服务器的 token。
// 现改为：优先读取 BUSINESS_JWT_SECRET，其次 JWT_SECRET，开发环境生成随机密钥。
func Load() *Config {
	// P1 修复: business-server 优先使用独立密钥 BUSINESS_JWT_SECRET
	jwtSecret := os.Getenv("BUSINESS_JWT_SECRET")
	if jwtSecret == "" {
		// 回退到 JWT_SECRET（向后兼容）
		jwtSecret = os.Getenv("JWT_SECRET")
	}
	if jwtSecret == "" {
		if os.Getenv("GO_ENV") == "production" {
			log.Fatal("JWT_SECRET or BUSINESS_JWT_SECRET environment variable must be set in production")
		}
		// P1 修复: 生成随机密钥替代固定默认值
		jwtSecret = generateRandomSecret(32)
		log.Println("WARNING: Generated random JWT_SECRET for development. " +
			"Set BUSINESS_JWT_SECRET env var for consistent sessions.")
	}

	// P1 修复: 校验密钥长度
	if len(jwtSecret) < 32 {
		if os.Getenv("GO_ENV") == "production" {
			log.Fatal("JWT_SECRET must be at least 32 bytes for security")
		}
		log.Printf("WARNING: JWT_SECRET is only %d bytes, recommend at least 32 bytes", len(jwtSecret))
	}

	allowedOrigins := parseEnvList("ALLOWED_ORIGINS", []string{"*"})

	return &Config{
		Port:            getEnv("PORT", "8081"),
		DBPath:          getEnv("DB_PATH", "./data/business.db"),
		JWTSecret:       jwtSecret,
		AllowedOrigins:  allowedOrigins,
		LogLevel:        getEnv("LOG_LEVEL", "info"),
		MaxTagDepth:     getEnvInt("MAX_TAG_DEPTH", 5),
		MaxFolderDepth:  getEnvInt("MAX_FOLDER_DEPTH", 10),
		MaxNoteSize:     getEnvInt("MAX_NOTE_SIZE", 10485760),
		PageRankDamping: getEnvFloat("PAGERANK_DAMPING", 0.85),
		PageRankIters:   getEnvInt("PAGERANK_ITERS", 100),
		RateLimit:       getEnvInt("RATE_LIMIT", 100),
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
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

func getEnvFloat(key string, fallback float64) float64 {
	if v := os.Getenv(key); v != "" {
		f, _ := strconv.ParseFloat(v, 64)
		return f
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
		s = strings.TrimSpace(s)
		if s != "" {
			result = append(result, s)
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
		log.Fatalf("Failed to generate random secret: %v", err)
	}
	return hex.EncodeToString(b)
}