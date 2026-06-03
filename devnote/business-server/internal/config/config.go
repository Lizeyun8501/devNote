package config

import (
	"os"
	"strconv"
)

// Config holds all configuration for the business server.
type Config struct {
	Port        string
	DBPath      string
	JWTSecret   string
	LogLevel    string
	MaxTagDepth int
	MaxFolderDepth int
	MaxNoteSize int
	PageRankDamping float64
	PageRankIters   int
}

// Load reads configuration from environment variables with sensible defaults.
func Load() *Config {
	return &Config{
		Port:            getEnv("PORT", "8081"),
		DBPath:          getEnv("DB_PATH", "./data/business.db"),
		JWTSecret:       getEnv("JWT_SECRET", "devnote-business-secret-key"),
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