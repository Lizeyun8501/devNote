package model

import (
	"time"

	"gorm.io/gorm"
)

// SharedNote 公开分享的笔记
type SharedNote struct {
	ID           string         `gorm:"primaryKey" json:"id"`
	UserID       string         `gorm:"index;size:64" json:"user_id"`
	NoteID       string         `gorm:"index;size:64" json:"note_id"`
	ShareToken   string         `gorm:"uniqueIndex;size:128" json:"share_token"` // 公开链接 token
	Title        string         `gorm:"size:256" json:"title"`
	Content      string         `gorm:"type:text" json:"content"` // 分享时的内容快照
	PasswordHash string         `gorm:"size:256" json:"-"`        // 密码哈希（bcrypt），空表示无密码
	HasPassword  bool           `json:"has_password"`
	ExpiresAt    *time.Time     `json:"expires_at"` // 过期时间，null 表示永不过期
	ViewCount    int64          `json:"view_count"`
	CreatedAt    time.Time      `json:"created_at"`
	UpdatedAt    time.Time      `json:"updated_at"`
	DeletedAt    gorm.DeletedAt `gorm:"index" json:"-"`
}
