package model

import (
	"time"

	"gorm.io/gorm"
)

type SyncRecord struct {
	ID         string         `gorm:"primaryKey" json:"id"`
	UserID     string         `gorm:"index;size:64" json:"user_id"`
	DeviceID   string         `gorm:"index;size:64" json:"device_id"`
	NoteID     string         `gorm:"index;size:64" json:"note_id"`
	Action     string         `gorm:"size:16" json:"action"`
	Version    int64          `gorm:"index" json:"version"`
	Timestamp  time.Time      `json:"timestamp"`
	Payload    string         `gorm:"type:text" json:"payload"`
	CreatedAt  time.Time      `json:"created_at"`
	DeletedAt  gorm.DeletedAt `gorm:"index" json:"-"`
}

const (
	ActionCreate = "create"
	ActionUpdate = "update"
	ActionDelete = "delete"
)
