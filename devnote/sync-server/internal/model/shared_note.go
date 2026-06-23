package model

import (
	"time"
)

// SharedNote 公开分享的笔记
type SharedNote struct {
	ID           string     `db:"id" json:"id"`
	UserID       string     `db:"user_id" json:"user_id"`
	NoteID       string     `db:"note_id" json:"note_id"`
	ShareToken   string     `db:"share_token" json:"share_token"`
	Title        string     `db:"title" json:"title"`
	Content      string     `db:"content" json:"content"`
	PasswordHash string     `db:"password_hash" json:"-"`
	HasPassword  bool       `db:"has_password" json:"has_password"`
	ExpiresAt    *time.Time `db:"expires_at" json:"expires_at"`
	ViewCount    int64      `db:"view_count" json:"view_count"`
	CreatedAt    time.Time  `db:"created_at" json:"created_at"`
	UpdatedAt    time.Time  `db:"updated_at" json:"updated_at"`
	DeletedAt    *time.Time `db:"deleted_at" json:"-"`
}
