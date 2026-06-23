package model

import (
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type User struct {
	ID          string    `db:"id" json:"id"`
	Username    string    `db:"username" json:"username"`
	Password    string    `db:"password" json:"-"`
	SRPSalt     []byte    `db:"srp_salt" json:"-"`
	SRPVerifier []byte    `db:"srp_verifier" json:"-"`
	SRPEnabled  bool      `db:"srp_enabled" json:"srp_enabled"`
	CreatedAt   time.Time `db:"created_at" json:"created_at"`
	UpdatedAt   time.Time `db:"updated_at" json:"updated_at"`
	DeletedAt   *time.Time `db:"deleted_at" json:"-"`
}

type Claims struct {
	UserID   string `json:"user_id"`
	Username string `json:"username"`
	jwt.RegisteredClaims
}

type RefreshToken struct {
	ID        string    `db:"id" json:"id"`
	UserID    string    `db:"user_id" json:"user_id"`
	Token     string    `db:"token" json:"token"`
	ExpiresAt time.Time `db:"expires_at" json:"expires_at"`
	CreatedAt time.Time `db:"created_at" json:"created_at"`
	Revoked   bool      `db:"revoked" json:"revoked"`
}
