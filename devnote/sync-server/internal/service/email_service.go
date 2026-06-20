package service

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// EmailService 邮件转笔记服务
type EmailService struct {
	db          *gorm.DB
	syncService *SyncService
	domain      string // 邮件域名，如 mail.devnote.app
}

// NewEmailService 创建邮件转笔记服务，并自动迁移别名表
func NewEmailService(db *gorm.DB, syncService *SyncService, domain string) *EmailService {
	s := &EmailService{
		db:          db,
		syncService: syncService,
		domain:      domain,
	}
	// 自动迁移邮件别名表
	if err := db.AutoMigrate(&UserEmailAlias{}); err != nil {
		log.Printf("failed to migrate email alias table: %v", err)
	}
	return s
}

// UserEmailAlias 用户邮件别名
type UserEmailAlias struct {
	ID        string    `gorm:"primaryKey" json:"id"`
	UserID    string    `gorm:"index" json:"user_id"`
	Alias     string    `gorm:"uniqueIndex" json:"alias"`      // 别名，如 abc123
	EmailAddr string    `gorm:"uniqueIndex" json:"email_addr"` // 完整邮箱 abc123@mail.devnote.app
	Active    bool      `json:"active"`
	CreatedAt time.Time `json:"created_at"`
}

// GenerateAlias 为用户生成邮件别名
func (s *EmailService) GenerateAlias(userID string) (*UserEmailAlias, error) {
	alias, err := generateRandomAlias(8)
	if err != nil {
		return nil, err
	}

	emailAddr := fmt.Sprintf("%s@%s", alias, s.domain)

	userAlias := &UserEmailAlias{
		ID:        uuid.New().String(),
		UserID:    userID,
		Alias:     alias,
		EmailAddr: emailAddr,
		Active:    true,
		CreatedAt: time.Now(),
	}

	if err := s.db.Create(userAlias).Error; err != nil {
		return nil, fmt.Errorf("create alias: %w", err)
	}
	return userAlias, nil
}

// GetAliasByUserID 获取用户的邮件别名
func (s *EmailService) GetAliasByUserID(userID string) (*UserEmailAlias, error) {
	var alias UserEmailAlias
	err := s.db.Where("user_id = ? AND active = ?", userID, true).First(&alias).Error
	if err != nil {
		return nil, err
	}
	return &alias, nil
}

// DeactivateAlias 停用别名
func (s *EmailService) DeactivateAlias(aliasID string) error {
	return s.db.Model(&UserEmailAlias{}).Where("id = ?", aliasID).Update("active", false).Error
}

// ProcessIncomingEmail 处理收到的邮件
// to: 收件人地址
// from: 发件人地址
// subject: 邮件主题
// textBody: 纯文本正文
// htmlBody: HTML 正文
func (s *EmailService) ProcessIncomingEmail(to, from, subject, textBody, htmlBody string) error {
	// 查找别名对应的用户
	var alias UserEmailAlias
	if err := s.db.Where("email_addr = ? AND active = ?", to, true).First(&alias).Error; err != nil {
		return fmt.Errorf("alias not found: %w", err)
	}

	// 转换邮件内容为 Markdown
	content := s.emailToMarkdown(subject, from, textBody, htmlBody)

	// 通过 SyncService 创建笔记
	noteID := uuid.New().String()
	noteContent := map[string]interface{}{
		"title":      subject,
		"content":    content,
		"source":     "email",
		"from":       from,
		"emailed_at": time.Now().UTC().Format(time.RFC3339),
	}
	contentJSON, err := json.Marshal(noteContent)
	if err != nil {
		return fmt.Errorf("encode note content: %w", err)
	}

	pushReq := &PushRequest{
		DeviceID: "email-gateway",
		Records: []SyncRecordInput{
			{
				NoteID:  noteID,
				Action:  "create",
				Version: 0,
				Payload: string(contentJSON),
			},
		},
	}

	if _, err := s.syncService.Push(alias.UserID, pushReq); err != nil {
		return fmt.Errorf("create note from email: %w", err)
	}

	return nil
}

// emailToMarkdown 将邮件转换为 Markdown 格式
func (s *EmailService) emailToMarkdown(subject, from, textBody, htmlBody string) string {
	var sb strings.Builder

	sb.WriteString(fmt.Sprintf("# %s\n\n", subject))
	sb.WriteString(fmt.Sprintf("> **发件人**: %s\n", from))
	sb.WriteString(fmt.Sprintf("> **时间**: %s\n\n", time.Now().Format("2006-01-02 15:04")))

	// 优先使用纯文本
	if textBody != "" {
		// 清理邮件签名和引用
		content := cleanEmailContent(textBody)
		sb.WriteString(content)
	} else if htmlBody != "" {
		// HTML 转 Markdown（简化版）
		content := htmlToMarkdown(htmlBody)
		sb.WriteString(content)
	}

	return sb.String()
}

// cleanEmailContent 清理邮件内容（移除签名、引用等）
func cleanEmailContent(text string) string {
	// 移除邮件签名（--- 之后的 content）
	if idx := strings.Index(text, "\n-- \n"); idx >= 0 {
		text = text[:idx]
	}
	// 移除引用回复
	quoteRegex := regexp.MustCompile(`(?m)^On .+ wrote:\n>`)
	text = quoteRegex.ReplaceAllString(text, "")
	// 移除行首引用符号
	lineQuoteRegex := regexp.MustCompile(`(?m)^> ?`)
	text = lineQuoteRegex.ReplaceAllString(text, "")
	return strings.TrimSpace(text)
}

// htmlToMarkdown 简化版 HTML 转 Markdown
func htmlToMarkdown(html string) string {
	// 移除 HTML 标签
	tagRegex := regexp.MustCompile(`<[^>]+>`)
	text := tagRegex.ReplaceAllString(html, "")
	// 解码 HTML 实体
	text = strings.ReplaceAll(text, "&nbsp;", " ")
	text = strings.ReplaceAll(text, "&amp;", "&")
	text = strings.ReplaceAll(text, "&lt;", "<")
	text = strings.ReplaceAll(text, "&gt;", ">")
	text = strings.ReplaceAll(text, "&quot;", "\"")
	text = strings.ReplaceAll(text, "&#39;", "'")
	return strings.TrimSpace(text)
}

func generateRandomAlias(length int) (string, error) {
	b := make([]byte, length)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
