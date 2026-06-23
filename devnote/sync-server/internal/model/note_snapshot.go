package model

import (
	"time"
)

type NoteSnapshot struct {
	ID        string     `db:"id" json:"id"`
	NoteID    string     `db:"note_id" json:"note_id"`
	UserID    string     `db:"user_id" json:"user_id"`
	Version   int64      `db:"version" json:"version"`
	Content   string     `db:"content" json:"content"`
	Checksum  string     `db:"checksum" json:"checksum"`
	CreatedAt time.Time  `db:"created_at" json:"created_at"`
	DeletedAt *time.Time `db:"deleted_at" json:"-"`
}
