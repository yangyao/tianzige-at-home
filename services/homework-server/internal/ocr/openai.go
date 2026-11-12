package ocr

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

const defaultOCRPrompt = `请把这张图片里的所有文字原样转成纯文本。
这是小学老师写在黑板或作业本上的作业安排，可能包含表格和手写体。
只输出文字，不要解释、不要总结。`

// OpenAICompatEngine 调用 OpenAI 兼容的 vision chat completions 接口
// （OpenAI、通义千问兼容模式、DeepSeek、vLLM、Ollama 等都能用）。
type OpenAICompatEngine struct {
	baseURL string
	apiKey  string
	model   string
	client  *http.Client
	prompt  string
}

// NewOpenAICompat 构造远程引擎。baseURL 例如 https://api.openai.com/v1。
func NewOpenAICompat(baseURL, apiKey, model string) *OpenAICompatEngine {
	return &OpenAICompatEngine{
		baseURL: strings.TrimRight(strings.TrimSpace(baseURL), "/"),
		apiKey:  strings.TrimSpace(apiKey),
		model:   strings.TrimSpace(model),
		client:  &http.Client{Timeout: 120 * time.Second},
		prompt:  defaultOCRPrompt,
	}
}

func (e *OpenAICompatEngine) Name() string { return "openai" }

func (e *OpenAICompatEngine) Status() string {
	if e.baseURL == "" || e.apiKey == "" || e.model == "" {
		return "unconfigured"
	}
	return "ok"
}

type chatMessage struct {
	Role    string `json:"role"`
	Content any    `json:"content"`
}

type imageURLPart struct {
	Type     string `json:"type"`
	ImageURL struct {
		URL string `json:"url"`
	} `json:"image_url"`
}

type textPart struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

func (e *OpenAICompatEngine) Recognize(ctx context.Context, img Image) (string, error) {
	if e.Status() != "ok" {
		return "", fmt.Errorf("%w: OCR 未配置", ErrUnavailable)
	}
	data, err := os.ReadFile(img.Path)
	if err != nil {
		return "", fmt.Errorf("读取图片失败: %w", err)
	}
	mime := img.MIME
	if mime == "" {
		mime = "image/jpeg"
	}
	b64 := base64.StdEncoding.EncodeToString(data)

	imgPart := imageURLPart{Type: "image_url"}
	imgPart.ImageURL.URL = "data:" + mime + ";base64," + b64
	body := map[string]any{
		"model":       e.model,
		"temperature": 0,
		"max_tokens":  2048,
		"messages": []chatMessage{{
			Role:    "user",
			Content: []any{textPart{Type: "text", Text: e.prompt}, imgPart},
		}},
	}
	payload, err := json.Marshal(body)
	if err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, e.baseURL+"/chat/completions", bytes.NewReader(payload))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+e.apiKey)

	resp, err := e.client.Do(req)
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
		return "", fmt.Errorf("OCR 请求失败: HTTP %d: %s", resp.StatusCode, truncate(string(raw), 200))
	}
	var out struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return "", fmt.Errorf("解析 OCR 响应失败: %w", err)
	}
	if len(out.Choices) == 0 {
		return "", fmt.Errorf("%w: 响应为空", ErrUnavailable)
	}
	text := strings.TrimSpace(out.Choices[0].Message.Content)
	if text == "" {
		return "", fmt.Errorf("OCR 未返回文字")
	}
	return text, nil
}

func truncate(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "…"
}
