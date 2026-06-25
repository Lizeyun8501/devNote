package config

import (
	"crypto/rand"
	"encoding/hex"
	"log"
	"strings"

	"github.com/spf13/viper"
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
	RedisURL        string
}

// Load reads configuration via Viper，优先级：环境变量 > 配置文件 > 默认值。
//
// 配置来源（P2-7 统一配置管理）：
//   - 配置文件: config.yaml（搜索路径: . / ./config / /etc/devnote/business-server）
//   - 环境变量: 保持原有变量名向后兼容（PORT / DB_PATH / BUSINESS_JWT_SECRET 等）
//   - 默认值: 与原实现一致
//
// P1 修复 (SEC-06): business-server 应使用独立的 JWT_SECRET，不与 sync-server 共用。
// 原实现两服务器共用同一密钥，任一泄露即可伪造另一服务器的 token。
// 现改为：优先读取 BUSINESS_JWT_SECRET，其次 JWT_SECRET，开发环境生成随机密钥。
func Load() *Config {
	v := viper.New()

	// 默认值
	v.SetDefault("port", "8081")
	v.SetDefault("db_path", "./data/business.db")
	v.SetDefault("migrations_path", "./migrations")
	v.SetDefault("log_level", "info")
	v.SetDefault("max_tag_depth", 5)
	v.SetDefault("max_folder_depth", 10)
	v.SetDefault("max_note_size", 10485760)
	v.SetDefault("pagerank_damping", 0.85)
	v.SetDefault("pagerank_iters", 100)
	v.SetDefault("rate_limit", 100)
	v.SetDefault("allowed_origins", "*")

	// 配置文件搜索路径
	v.SetConfigName("config")
	v.SetConfigType("yaml")
	v.AddConfigPath(".")
	v.AddConfigPath("./config")
	v.AddConfigPath("/etc/devnote/business-server")
	if err := v.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			log.Printf("WARNING: 读取配置文件失败: %v", err)
		}
	}

	// 环境变量绑定（保持原有变量名，向后兼容）
	v.BindEnv("port", "PORT")
	v.BindEnv("db_path", "DB_PATH")
	v.BindEnv("migrations_path", "MIGRATIONS_PATH")
	v.BindEnv("jwt_secret", "BUSINESS_JWT_SECRET", "JWT_SECRET")
	v.BindEnv("allowed_origins", "ALLOWED_ORIGINS")
	v.BindEnv("log_level", "LOG_LEVEL")
	v.BindEnv("max_tag_depth", "MAX_TAG_DEPTH")
	v.BindEnv("max_folder_depth", "MAX_FOLDER_DEPTH")
	v.BindEnv("max_note_size", "MAX_NOTE_SIZE")
	v.BindEnv("pagerank_damping", "PAGERANK_DAMPING")
	v.BindEnv("pagerank_iters", "PAGERANK_ITERS")
	v.BindEnv("rate_limit", "RATE_LIMIT")
	v.BindEnv("redis_url", "REDIS_URL")
	v.BindEnv("go_env", "GO_ENV")

	// JWT 密钥处理（P1 SEC-06: business-server 优先使用独立密钥）
	jwtSecret := v.GetString("jwt_secret")
	if jwtSecret == "" {
		if v.GetString("go_env") == "production" {
			log.Fatal("JWT_SECRET or BUSINESS_JWT_SECRET must be set in production (env or config.yaml)")
		}
		jwtSecret = generateRandomSecret(32)
		log.Println("WARNING: Generated random JWT_SECRET for development. " +
			"Set BUSINESS_JWT_SECRET env var or config.yaml for consistent sessions.")
	}
	if len(jwtSecret) < 32 {
		if v.GetString("go_env") == "production" {
			log.Fatal("JWT_SECRET must be at least 32 bytes for security")
		}
		log.Printf("WARNING: JWT_SECRET is only %d bytes, recommend at least 32 bytes", len(jwtSecret))
	}

	return &Config{
		Port:            v.GetString("port"),
		DBPath:          v.GetString("db_path"),
		MigrationsPath:  v.GetString("migrations_path"),
		JWTSecret:       jwtSecret,
		AllowedOrigins:  parseOrigins(v.GetString("allowed_origins")),
		LogLevel:        v.GetString("log_level"),
		MaxTagDepth:     v.GetInt("max_tag_depth"),
		MaxFolderDepth:  v.GetInt("max_folder_depth"),
		MaxNoteSize:     v.GetInt("max_note_size"),
		PageRankDamping: v.GetFloat64("pagerank_damping"),
		PageRankIters:   v.GetInt("pagerank_iters"),
		RateLimit:       v.GetInt("rate_limit"),
		RedisURL:        v.GetString("redis_url"),
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

// ConfigFilePath 返回 Viper 实际加载的配置文件路径（用于启动日志）。
// 未加载配置文件时返回空字符串。
func ConfigFilePath() string {
	v := viper.New()
	v.SetConfigName("config")
	v.SetConfigType("yaml")
	v.AddConfigPath(".")
	v.AddConfigPath("./config")
	v.AddConfigPath("/etc/devnote/business-server")
	if err := v.ReadInConfig(); err != nil {
		return ""
	}
	return v.ConfigFileUsed()
}
