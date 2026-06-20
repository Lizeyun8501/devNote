package service

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"github.com/devnote/sync-server/internal/model"
	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

type ShareService struct {
	db *gorm.DB
}

func NewShareService(db *gorm.DB) *ShareService {
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

	if err := s.db.Create(share).Error; err != nil {
		return nil, fmt.Errorf("create share: %w", err)
	}
	return share, nil
}

// GetShareByToken 通过 token 获取分享内容（公开访问，需验证密码和有效期）
func (s *ShareService) GetShareByToken(token, password string) (*model.SharedNote, error) {
	var share model.SharedNote
	err := s.db.Where("share_token = ?", token).First(&share).Error
	if err != nil {
		return nil, fmt.Errorf("share not found: %w", err)
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
	s.db.Model(&share).UpdateColumn("view_count", gorm.Expr("view_count + 1"))

	return &share, nil
}

// ListUserShares 列出用户的所有分享
func (s *ShareService) ListUserShares(userID string) ([]model.SharedNote, error) {
	var shares []model.SharedNote
	err := s.db.Where("user_id = ?", userID).Order("created_at DESC").Find(&shares).Error
	return shares, err
}

// DeleteShare 删除分享
func (s *ShareService) DeleteShare(userID, shareID string) error {
	return s.db.Where("id = ? AND user_id = ?", shareID, userID).Delete(&model.SharedNote{}).Error
}

// UpdateShareContent 更新分享内容（重新发布）
func (s *ShareService) UpdateShareContent(userID, shareID, content string) error {
	return s.db.Model(&model.SharedNote{}).
		Where("id = ? AND user_id = ?", shareID, userID).
		Update("content", content).Error
}

func generateShareToken() (string, error) {
	b := make([]byte, 24)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
