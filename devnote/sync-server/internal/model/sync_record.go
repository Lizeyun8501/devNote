package model

import (
	"time"
)

type SyncRecord struct {
	ID         string     `db:"id" json:"id"`
	UserID     string     `db:"user_id" json:"user_id"`
	DeviceID   string     `db:"device_id" json:"device_id"`
	NoteID     string     `db:"note_id" json:"note_id"`
	Action     string     `db:"action" json:"action"`
	Version    int64      `db:"version" json:"version"`
	Timestamp  time.Time  `db:"timestamp" json:"timestamp"`
	Payload    string     `db:"payload" json:"payload"`
	CreatedAt  time.Time  `db:"created_at" json:"created_at"`
	DeletedAt  *time.Time `db:"deleted_at" json:"-"`
}

const (
	ActionCreate = "create"
	ActionUpdate = "update"
	ActionDelete = "delete"
)
