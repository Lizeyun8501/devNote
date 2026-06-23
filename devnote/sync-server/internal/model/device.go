package model

import (
	"time"
)

type Device struct {
	ID          string     `db:"id" json:"id"`
	UserID      string     `db:"user_id" json:"user_id"`
	DeviceName  string     `db:"device_name" json:"device_name"`
	DeviceType  string     `db:"device_type" json:"device_type"`
	LastSyncAt  time.Time  `db:"last_sync_at" json:"last_sync_at"`
	LastSyncVer int64      `db:"last_sync_ver" json:"last_sync_ver"`
	CreatedAt   time.Time  `db:"created_at" json:"created_at"`
	UpdatedAt   time.Time  `db:"updated_at" json:"updated_at"`
	DeletedAt   *time.Time `db:"deleted_at" json:"-"`
}
