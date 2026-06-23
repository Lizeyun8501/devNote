package service

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"time"

	"github.com/devnote/sync-server/internal/model"
	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"golang.org/x/crypto/bcrypt"
)

type ShareService struct {
	db *sqlx.DB
}

func NewShareService(db *sqlx.DB) *ShareService {
	return &ShareService{db: db}
}

// CreateShare 创建分享链接
func (s *ShareService) CreateShare(userID, noteID, title, content, password string, expiresAt *time.Time) (*model.SharedNote, error) {
	token, err := generateShareToken()
	if err != nil {
		return nil, fmt.Errorf("generate token: %w", err)
	}

	var passwordHash string
	hasPassword := false
	if password != "" {
		hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
		if err != nil {
			return nil, fmt.Errorf("hash password: %w", err)
		}
		passwordHash = string(hash)
		hasPassword = true
	}

	share := &model.SharedNote{
		ID:           uuid.New().String(),
		UserID:       userID,
		NoteID:       noteID,
		ShareToken:   token,
		Title:        title,
		Content:      content,
		PasswordHash: passwordHash,
		HasPassword:  hasPassword,
		ExpiresAt:    expiresAt,
	}

	now := time.Now()
	_, err = s.db.Exec(
		`INSERT INTO shared_notes (id, user_id, note_id, share_token, title, content, password_hash, has_password, expires_at, view_count, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)`,
		share.ID, share.UserID, share.NoteID, share.ShareToken, share.Title, share.Content, share.PasswordHash, share.HasPassword, share.ExpiresAt, now, now,
	)
	if err != nil {
		return nil, fmt.Errorf("create share: %w", err)
	}
	share.CreatedAt = now
	share.UpdatedAt = now
	share.ViewCount = 0
	return share, nil
}

// GetShareByToken 通过 token 获取分享内容（公开访问，需验证密码和有效期）
func (s *ShareService) GetShareByToken(token, password string) (*model.SharedNote, error) {
	var share model.SharedNote
	err := s.db.Get(&share,
		`SELECT * FROM shared_notes WHERE share_token = ? AND deleted_at IS NULL`, token)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, errors.New("share not found")
		}
		return nil, fmt.Errorf("query share: %w", err)
	}

	// 检查过期
	if share.ExpiresAt != nil && share.ExpiresAt.Before(time.Now()) {
		return nil, errors.New("share expired")
	}

	// 验证密码
	if share.HasPassword {
		if password == "" {
			return nil, errors.New("password required")
		}
		if err := bcrypt.CompareHashAndPassword([]byte(share.PasswordHash), []byte(password)); err != nil {
			return nil, errors.New("invalid password")
		}
	}

	// 增加浏览数
	// P3 修复 (P3-9): 原实现忽略 UpdateColumn 错误，浏览数统计失败时无任何感知
	// 浏览数为非关键统计数据，失败时记录日志但不影响分享访问
	_, err = s.db.Exec(
		`UPDATE shared_notes SET view_count = view_count + 1 WHERE id = ?`, share.ID)
	if err != nil {
		log.Printf("update share view_count failed (share_id=%s): %v", share.ID, err)
	}

	return &share, nil
}

// ListUserShares 列出用户的所有分享
func (s *ShareService) ListUserShares(userID string) ([]model.SharedNote, error) {
	var shares []model.SharedNote
	err := s.db.Select(&shares,
		`SELECT * FROM shared_notes WHERE user_id = ? AND deleted_at IS NULL ORDER BY created_at DESC`,
		userID)
	return shares, err
}

// DeleteShare 删除分享
func (s *ShareService) DeleteShare(userID, shareID string) error {
	_, err := s.db.Exec(
		`UPDATE shared_notes SET deleted_at = ? WHERE id = ? AND user_id = ?`,
		time.Now(), shareID, userID)
	return err
}

// UpdateShareContent 更新分享内容（重新发布）
func (s *ShareService) UpdateShareContent(userID, shareID, content string) error {
	_, err := s.db.Exec(
		`UPDATE shared_notes SET content = ?, updated_at = ? WHERE id = ? AND user_id = ?`,
		content, time.Now(), shareID, userID)
	return err
}

func generateShareToken() (string, error) {
	b := make([]byte, 24)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
