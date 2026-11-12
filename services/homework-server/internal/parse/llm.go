package parse

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

const llmSystemPrompt = `你是小学作业整理助手。把 OCR 文本整理成按科目分组的作业条目，只输出 JSON 数组，不要输出解释或 Markdown 代码块。
格式：[{"subject":"语文","items":["朗读课文三遍"]}]
要求：
1. subject 只能是 语文、数学、英语、科学、道法、其他 之一，判断不了就用「其他」；
2. items 每条是一个完整可执行的作业动作，去掉题号前缀与 OCR 噪声，保留页码和题号；
3. 不要编造原文没有的内容，没有作业的科目不要输出；
4. 老师备注可以作为分科线索，但它不是作业内容本身；科目贴纸、页码标记、识别说明不是作业，不要变成条目。
5. 题号、页码、单位和复习范围不能擅自改写；看不清的内容保留标记，不补全、不猜测。`

// LLMParser 调 OpenAI 兼容 chat 接口做分科。温度 0，JSON 解析失败自动重试一次。
type LLMParser struct {
	baseURL    string
	apiKey     string
	model      string
	client     *http.Client
	options    map[string]any
	allowNoKey bool
}

// NewLLMParser 构造分科器。baseURL 例如 https://api.openai.com/v1。
func NewLLMParser(baseURL, apiKey, model string) *LLMParser {
	return &LLMParser{
		baseURL: strings.TrimRight(strings.TrimSpace(baseURL), "/"),
		apiKey:  strings.TrimSpace(apiKey),
		model:   strings.TrimSpace(model),
		client:  &http.Client{Timeout: 120 * time.Second},
	}
}

func NewZAIParser(baseURL, apiKey, model string) *LLMParser {
	p := NewLLMParser(baseURL, apiKey, model)
	p.options = map[string]any{
		"temperature": 1,
		"max_tokens":  16384,
		"thinking":    map[string]string{"type": "enabled"},
	}
	return p
}

func (p *LLMParser) Name() string {
	if p.options != nil {
		return "zai"
	}
	return "openai"
}

func (p *LLMParser) AllowNoKey(allow bool) { p.allowNoKey = allow }

func (p *LLMParser) Parse(ctx context.Context, ocrText, note string) ([]Group, error) {
	if p.baseURL == "" || (p.apiKey == "" && !p.allowNoKey) || p.model == "" {
		return nil, fmt.Errorf("%w: 分科模型未配置", ErrUnavailable)
	}
	user := "老师备注：" + orNone(note) + "\n\nOCR 文本：\n" + ocrText
	var lastErr error
	for attempt := 0; attempt < 2; attempt++ {
		text, err := p.chat(ctx, user)
		if err != nil {
			return nil, err
		}
		groups, err := decodeGroups(text)
		if err == nil {
			return groups, nil
		}
		lastErr = err
		user = "上一次输出无法解析（" + err.Error() + "）。请严格只输出 JSON 数组：\n\n" + user
	}
	return nil, fmt.Errorf("分科结果解析失败: %w", lastErr)
}

func (p *LLMParser) chat(ctx context.Context, user string) (string, error) {
	body := map[string]any{
		"model":       p.model,
		"temperature": 0,
		"messages": []map[string]string{
			{"role": "system", "content": llmSystemPrompt},
			{"role": "user", "content": user},
		},
	}
	for key, value := range p.options {
		body[key] = value
	}
	payload, err := json.Marshal(body)
	if err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.baseURL+"/chat/completions", bytes.NewReader(payload))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	if p.apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+p.apiKey)
	}
	resp, err := p.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrUnavailable, err)
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return "", fmt.Errorf("%w: 读取响应失败: %v", ErrUnavailable, err)
	}
	if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= 500 {
		return "", fmt.Errorf("%w: HTTP %d", ErrUnavailable, resp.StatusCode)
	}
	if resp.StatusCode != http.StatusOK {
		message := string(raw)
		if p.apiKey != "" {
			message = strings.ReplaceAll(message, p.apiKey, "[已隐藏]")
		}
		return "", fmt.Errorf("分科请求失败: HTTP %d: %s", resp.StatusCode, truncate(message, 200))
	}
	var out struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return "", fmt.Errorf("解析模型响应失败: %w", err)
	}
	if len(out.Choices) == 0 {
		return "", fmt.Errorf("%w: 响应为空", ErrUnavailable)
	}
	return out.Choices[0].Message.Content, nil
}

type rawGroup struct {
	Subject string   `json:"subject"`
	Items   []string `json:"items"`
}

// decodeGroups 容忍 Markdown 代码块与前后废话，只截取第一个 JSON 数组。
func decodeGroups(text string) ([]Group, error) {
	start := strings.Index(text, "[")
	end := strings.LastIndex(text, "]")
	if start < 0 || end <= start {
		return nil, fmt.Errorf("响应里没有 JSON 数组")
	}
	var raw []rawGroup
	if err := json.Unmarshal([]byte(text[start:end+1]), &raw); err != nil {
		return nil, err
	}
	groups := make([]Group, 0, len(raw))
	for _, g := range raw {
		items := CleanItems(g.Items)
		if len(items) == 0 {
			continue
		}
		groups = append(groups, Group{Subject: NormalizeSubject(g.Subject), Items: items})
	}
	if len(groups) == 0 {
		return nil, ErrEmpty
	}
	return groups, nil
}

func orNone(s string) string {
	if strings.TrimSpace(s) == "" {
		return "（无）"
	}
	return s
}

func truncate(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "…"
}
