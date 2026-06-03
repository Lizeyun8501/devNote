package model

import (
	"time"

	"github.com/golang-jwt/jwt/v5"
	"gorm.io/gorm"
)

type User struct {
	ID          string         `gorm:"primaryKey" json:"id"`
	Username    string         `gorm:"uniqueIndex;size:64" json:"username"`
	Password    string         `gorm:"size:256" json:"-"`
	SRPSalt     []byte         `gorm:"type:blob" json:"-"`
	SRPVerifier []byte         `gorm:"type:blob" json:"-"`
	SRPEnabled  bool           `gorm:"default:false" json:"srp_enabled"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}

type Claims struct {
	UserID   string `json:"user_id"`
	Username string `json:"username"`
	jwt.RegisteredClaims
}

type RefreshToken struct {
	ID        string    `json:"id" gorm:"primaryKey"`
	UserID    string    `json:"user_id" gorm:"index"`
	Token     string    `json:"token" gorm:"uniqueIndex"`
	ExpiresAt time.Time `json:"expires_at"`
	CreatedAt time.Time `json:"created_at"`
	Revoked   bool      `json:"revoked"`
}
