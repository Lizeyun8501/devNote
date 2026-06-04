package config

import (
	"log"
	"os"
	"strconv"
	"strings"
)

// Config holds all configuration for the business server.
type Config struct {
	Port            string
	DBPath          string
	JWTSecret       string
	AllowedOrigins  []string
	LogLevel        string
	MaxTagDepth     int
	MaxFolderDepth  int
	MaxNoteSize     int
	PageRankDamping float64
	PageRankIters   int
}

// Load reads configuration from environment variables with sensible defaults.
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