package model

import (
	"time"

	"gorm.io/gorm"
)

type Device struct {
	ID          string         `gorm:"primaryKey" json:"id"`
	UserID      string         `gorm:"index;size:64" json:"user_id"`
	DeviceName  string         `gorm:"size:128" json:"device_name"`
	DeviceType  string         `gorm:"size:32" json:"device_type"`
	LastSyncAt  time.Time      `json:"last_sync_at"`
	LastSyncVer int64          `json:"last_sync_ver"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}
