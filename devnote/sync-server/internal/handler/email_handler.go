package handler

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net/http"

	"github.com/devnote/sync-server/internal/service"
	"github.com/gin-gonic/gin"
)

// EmailHandler 处理邮件转笔记相关的 HTTP 请求
type EmailHandler struct {
	emailService  *service.EmailService
	webhookSecret string // Webhook HMAC 验证密钥
}

func NewEmailHandler(emailService *service.EmailService, webhookSecret string) *EmailHandler {
	return &EmailHandler{
		emailService:  emailService,
		webhookSecret: webhookSecret,
	}
}

// IncomingEmailWebhook 接收邮件 Webhook（来自 SendGrid/Mailgun/SES 等）
//
// P0 修复: 原实现直接比较请求头值与密钥本身（signature != webhookSecret），
// 这意味着密钥以明文形式在请求头中传输，完全失去签名意义。
// 现改为标准 HMAC-SHA256 验证：客户端用密钥对请求体做 HMAC，将结果
// 放入 X-Webhook-Signature 头（十六进制编码）；服务端用同一密钥对
// 请求体重新计算 HMAC 并用 hmac.Equal 常量时间比较。
func (h *EmailHandler) IncomingEmailWebhook(c *gin.Context) {
	if h.webhookSecret != "" {
		signature := c.GetHeader("X-Webhook-Signature")
		if signature == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "missing signature"})
			return
		}

		// 读取请求体用于 HMAC 计算
		body, err := io.ReadAll(c.Request.Body)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "failed to read body"})
			return
		}

		// 计算期望的 HMAC-SHA256 签名
		mac := hmac.New(sha256.New, []byte(h.webhookSecret))
		mac.Write(body)
		expectedSig := hex.EncodeToString(mac.Sum(nil))

		// 常量时间比较防止时序攻击
		if !hmac.Equal([]byte(signature), []byte(expectedSig)) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid signature"})
			return
		}

		// 将 body 重新放回 c.Request.Body 供后续 ShouldBindJSON 使用
		c.Request.Body = io.NopCloser(bytes.NewReader(body))
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
