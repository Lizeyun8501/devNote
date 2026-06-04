package model

import (
	"time"

	"gorm.io/gorm"
)

type NoteSnapshot struct {
	ID        string         `gorm:"primaryKey" json:"id"`
	NoteID    string         `gorm:"index;size:64" json:"note_id"`
	UserID    string         `gorm:"index;size:64" json:"user_id"`
	Version   int64          `json:"version"`
	Content   string         `gorm:"type:text" json:"content"`
	Checksum  string         `gorm:"size:64" json:"checksum"`
	CreatedAt time.Time      `json:"created_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}
