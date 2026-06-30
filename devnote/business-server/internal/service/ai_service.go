// Package service provides AI service integration for the business server.
//
// P0 架构修复 (P3): AI 服务端落地
// 提供 OpenAI 兼容的 AI 服务抽象，支持 Ollama 等本地模型供应商。
// 初始实现支持：笔记摘要、文本改写、自动补全、标签推荐。
package service

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// ── AI 服务提供商接口 ──────────────────────────────────────────────────

// AIServiceProvider 定义 AI 服务抽象接口
// 支持 Ollama、OpenAI、Anthropic 等后端，通过配置切换
type AIServiceProvider interface {
	// Chat 发送聊天补全请求
	Chat(model string, messages []ChatMessage) (*ChatResponse, error)
	// Embeddings 生成文本嵌入向量
	Embeddings(model string, texts []string) ([]EmbeddingResponse, error)
	// ListModels 列出可用模型
	ListModels() ([]ModelInfo, error)
	// Health 检查服务健康状态
	Health() error
}

// ChatMessage 聊天消息
type ChatMessage struct {
	Role    string `json:"role"`    // "system", "user", "assistant"
	Content string `json:"content"` // 消息内容
}

// ChatResponse 聊天补全响应
type ChatResponse struct {
	Content string `json:"content"`
	Usage   Usage  `json:"usage"`
}

// EmbeddingResponse 嵌入向量响应
type EmbeddingResponse struct {
	Embedding []float32 `json:"embedding"`
}

// ModelInfo 模型信息
type ModelInfo struct {
	Name     string `json:"name"`
	Size     string `json:"size"`
	Modified string `json:"modified"`
}

// Usage Token 使用统计
type Usage struct {
	PromptTokens     int `json:"prompt_tokens"`
	CompletionTokens int `json:"completion_tokens"`
	TotalTokens      int `json:"total_tokens"`
}

// ── Ollama 实现 ────────────────────────────────────────────────────────

// OllamaProvider 实现 AIServiceProvider，对接 Ollama API
type OllamaProvider struct {
	baseURL    string
	httpClient *http.Client
}

// NewOllamaProvider 创建 Ollama AI 服务提供商
func NewOllamaProvider(baseURL string) *OllamaProvider {
	return &OllamaProvider{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// ollamaChatRequest Ollama API 请求格式
type ollamaChatRequest struct {
	Model    string        `json:"model"`
	Messages []ChatMessage `json:"messages"`
	Stream   bool          `json:"stream"`
}

// ollamaChatResponse Ollama API 响应格式
type ollamaChatResponse struct {
	Message ChatMessage `json:"message"`
}

// ollamaListResponse Ollama 模型列表响应
type ollamaListResponse struct {
	Models []struct {
		Name       string `json:"name"`
		Size       int64  `json:"size"`
		ModifiedAt string `json:"modified_at"`
	} `json:"models"`
}

// ollamaEmbedRequest Ollama 嵌入请求
type ollamaEmbedRequest struct {
	Model string `json:"model"`
	Input string `json:"input"`
}

// ollamaEmbedResponse Ollama 嵌入响应
type ollamaEmbedResponse struct {
	Embedding []float32 `json:"embedding"`
}

// Chat 发送聊天补全请求到 Ollama
func (p *OllamaProvider) Chat(model string, messages []ChatMessage) (*ChatResponse, error) {
	reqBody := ollamaChatRequest{
		Model:    model,
		Messages: messages,
		Stream:   false,
	}

	data, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("marshal chat request: %w", err)
	}

	resp, err := p.httpClient.Post(
		p.baseURL+"/api/chat",
		"application/json",
		bytes.NewReader(data),
	)
	if err != nil {
		return nil, fmt.Errorf("ollama chat request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("ollama chat error %d: %s", resp.StatusCode, string(body))
	}

	var chatResp ollamaChatResponse
	if err := json.NewDecoder(resp.Body).Decode(&chatResp); err != nil {
		return nil, fmt.Errorf("decode chat response: %w", err)
	}

	return &ChatResponse{
		Content: chatResp.Message.Content,
		Usage:   Usage{TotalTokens: 0}, // Ollama 不返回 token 计数
	}, nil
}

// Embeddings 生成文本嵌入向量
func (p *OllamaProvider) Embeddings(model string, texts []string) ([]EmbeddingResponse, error) {
	results := make([]EmbeddingResponse, 0, len(texts))

	for _, text := range texts {
		reqBody := ollamaEmbedRequest{
			Model: model,
			Input: text,
		}

		data, err := json.Marshal(reqBody)
		if err != nil {
			return nil, fmt.Errorf("marshal embed request: %w", err)
		}

		resp, err := p.httpClient.Post(
			p.baseURL+"/api/embeddings",
			"application/json",
			bytes.NewReader(data),
		)
		if err != nil {
			return nil, fmt.Errorf("ollama embed request: %w", err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			return nil, fmt.Errorf("ollama embed error %d: %s", resp.StatusCode, string(body))
		}

		var embedResp ollamaEmbedResponse
		if err := json.NewDecoder(resp.Body).Decode(&embedResp); err != nil {
			return nil, fmt.Errorf("decode embed response: %w", err)
		}

		results = append(results, EmbeddingResponse{Embedding: embedResp.Embedding})
	}

	return results, nil
}

// ListModels 列出可用模型
func (p *OllamaProvider) ListModels() ([]ModelInfo, error) {
	resp, err := p.httpClient.Get(p.baseURL + "/api/tags")
	if err != nil {
		return nil, fmt.Errorf("ollama list models: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("ollama list models error %d: %s", resp.StatusCode, string(body))
	}

	var listResp ollamaListResponse
	if err := json.NewDecoder(resp.Body).Decode(&listResp); err != nil {
		return nil, fmt.Errorf("decode list models response: %w", err)
	}

	models := make([]ModelInfo, 0, len(listResp.Models))
	for _, m := range listResp.Models {
		size := fmt.Sprintf("%.1f GB", float64(m.Size)/(1024*1024*1024))
		models = append(models, ModelInfo{
			Name:     m.Name,
			Size:     size,
			Modified: m.ModifiedAt,
		})
	}

	return models, nil
}

// Health 检查 Ollama 服务健康状态
func (p *OllamaProvider) Health() error {
	resp, err := p.httpClient.Get(p.baseURL + "/api/tags")
	if err != nil {
		return fmt.Errorf("ollama health check: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("ollama health check returned %d", resp.StatusCode)
	}

	return nil
}

// ── AI 服务管理器 ──────────────────────────────────────────────────────

// AIServiceManager 管理 AI 服务提供商的生命周期
type AIServiceManager struct {
	provider AIServiceProvider
}

// NewAIServiceManager 创建 AI 服务管理器
func NewAIServiceManager(provider AIServiceProvider) *AIServiceManager {
	return &AIServiceManager{provider: provider}
}

// SummarizeNote 生成笔记摘要
func (m *AIServiceManager) SummarizeNote(content string, model string) (string, error) {
	messages := []ChatMessage{
		{Role: "system", Content: "你是一个专业的笔记摘要助手。请用简洁的中文总结以下笔记内容，不超过 200 字。"},
		{Role: "user", Content: content},
	}

	resp, err := m.provider.Chat(model, messages)
	if err != nil {
		return "", fmt.Errorf("summarize note: %w", err)
	}

	return resp.Content, nil
}

// RewriteText 改写文本
func (m *AIServiceManager) RewriteText(content string, style string, model string) (string, error) {
	prompt := fmt.Sprintf("你是一个专业的文本改写助手。请将以下文本改写为%s风格，保持原意不变。", style)
	messages := []ChatMessage{
		{Role: "system", Content: prompt},
		{Role: "user", Content: content},
	}

	resp, err := m.provider.Chat(model, messages)
	if err != nil {
		return "", fmt.Errorf("rewrite text: %w", err)
	}

	return resp.Content, nil
}

// SuggestTags 推荐标签
func (m *AIServiceManager) SuggestTags(content string, model string) ([]string, error) {
	messages := []ChatMessage{
		{Role: "system", Content: "你是一个专业的标签推荐助手。根据笔记内容，推荐 3-5 个最相关的标签。只返回标签名称，用逗号分隔，不要其他文字。"},
		{Role: "user", Content: content},
	}

	resp, err := m.provider.Chat(model, messages)
	if err != nil {
		return nil, fmt.Errorf("suggest tags: %w", err)
	}

	// 简单解析逗号分隔的标签
	tags := splitAndTrim(resp.Content, ",")
	return tags, nil
}

// AutoComplete 自动补全文本
func (m *AIServiceManager) AutoComplete(prefix string, model string) (string, error) {
	messages := []ChatMessage{
		{Role: "system", Content: "你是一个专业的文本补全助手。请根据上下文自然地补全文本，只返回补全内容，不要重复已有内容。"},
		{Role: "user", Content: prefix},
	}

	resp, err := m.provider.Chat(model, messages)
	if err != nil {
		return "", fmt.Errorf("autocomplete: %w", err)
	}

	return resp.Content, nil
}

// splitAndTrim 分割字符串并去除空白
func splitAndTrim(s, sep string) []string {
	parts := make([]string, 0)
	for _, p := range splitString(s, sep) {
		trimmed := trimSpaces(p)
		if trimmed != "" {
			parts = append(parts, trimmed)
		}
	}
	return parts
}

// splitString 简单的字符串分割（避免导入 strings 包额外依赖）
func splitString(s, sep string) []string {
	var result []string
	start := 0
	for i := 0; i <= len(s)-len(sep); i++ {
		if s[i:i+len(sep)] == sep {
			result = append(result, s[start:i])
			start = i + len(sep)
		}
	}
	result = append(result, s[start:])
	return result
}

// trimSpaces 去除首尾空格
func trimSpaces(s string) string {
	start := 0
	end := len(s)
	for start < end && (s[start] == ' ' || s[start] == '\t' || s[start] == '\n' || s[start] == '\r') {
		start++
	}
	for end > start && (s[end-1] == ' ' || s[end-1] == '\t' || s[end-1] == '\n' || s[end-1] == '\r') {
		end--
	}
	return s[start:end]
}