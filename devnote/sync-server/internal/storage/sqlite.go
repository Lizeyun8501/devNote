package storage

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/devnote/sync-server/internal/model"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

type SQLiteStorage struct {
	DB *gorm.DB
}

func NewSQLiteStorage(dbPath string) (*SQLiteStorage, error) {
	dir := filepath.Dir(dbPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("create db directory: %w", err)
	}

	db, err := gorm.Open(sqlite.Open(dbPath), &gorm.Config{})
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}

	if err := db.AutoMigrate(&model.User{}, &model.Device{}, &model.SyncRecord{}, &model.NoteSnapshot{}, &model.RefreshToken{}, &model.SharedNote{}); err != nil {
		return nil, fmt.Errorf("migrate database: %w", err)
	}

	return &SQLiteStorage{DB: db}, nil
}

func (s *SQLiteStorage) Close() error {
	sqlDB, err := s.DB.DB()
	if err != nil {
		return err
	}
	return sqlDB.Close()
}
