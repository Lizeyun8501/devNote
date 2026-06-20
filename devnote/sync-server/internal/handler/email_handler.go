package handler

import (
	"net/http"

	"github.com/devnote/sync-server/internal/service"
	"github.com/gin-gonic/gin"
)

// EmailHandler 处理邮件转笔记相关的 HTTP 请求
type EmailHandler struct {
	emailService  *service.EmailService
	webhookSecret string // Webhook 验证密钥
}

func NewEmailHandler(emailService *service.EmailService, webhookSecret string) *EmailHandler {
	return &EmailHandler{
		emailService:  emailService,
		webhookSecret: webhookSecret,
	}
}

// IncomingEmailWebhook 接收邮件 Webhook（来自 SendGrid/Mailgun/SES 等）
func (h *EmailHandler) IncomingEmailWebhook(c *gin.Context) {
	// 验证 Webhook 签名（根据邮件服务商不同）
	signature := c.GetHeader("X-Webhook-Signature")
	if h.webhookSecret != "" && signature != h.webhookSecret {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid signature"})
		return
	}

	var req struct {
		To       string `json:"to"`
		From     string `json:"from"`
		Subject  string `json:"subject"`
		TextBody string `json:"text_body"`
		HTMLBody string `json:"html_body"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.emailService.ProcessIncomingEmail(req.To, req.From, req.Subject, req.TextBody, req.HTMLBody); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "processed"})
}

// GetUserAlias 获取用户的邮件别名
func (h *EmailHandler) GetUserAlias(c *gin.Context) {
	userID := c.GetString("user_id")

	alias, err := h.emailService.GetAliasByUserID(userID)
	if err != nil {
		// 别名不存在，创建新别名
		newAlias, err := h.emailService.GenerateAlias(userID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{
			"alias":      newAlias.Alias,
			"email_addr": newAlias.EmailAddr,
			"active":     newAlias.Active,
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"alias":      alias.Alias,
		"email_addr": alias.EmailAddr,
		"active":     alias.Active,
	})
}

// RegenerateAlias 重新生成邮件别名
func (h *EmailHandler) RegenerateAlias(c *gin.Context) {
	userID := c.GetString("user_id")

	// 停用旧别名
	oldAlias, err := h.emailService.GetAliasByUserID(userID)
	if err == nil {
		h.emailService.DeactivateAlias(oldAlias.ID)
	}

	// 生成新别名
	newAlias, err := h.emailService.GenerateAlias(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"alias":      newAlias.Alias,
		"email_addr": newAlias.EmailAddr,
		"active":     newAlias.Active,
	})
}
