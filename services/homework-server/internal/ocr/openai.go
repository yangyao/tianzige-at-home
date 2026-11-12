package ocr

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"image"
	"image/png"
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
// 适用于提供 Chat Completions 和 image_url 输入的云端或本地模型服务。
type OpenAICompatEngine struct {
	baseURL    string
	apiKey     string
	model      string
	client     *http.Client
	prompt     string
	name       string
	options    map[string]any
	allowNoKey bool
}

// NewOpenAICompat 构造远程引擎。baseURL 例如 https://api.openai.com/v1。
func NewOpenAICompat(baseURL, apiKey, model string) *OpenAICompatEngine {
	return &OpenAICompatEngine{
		baseURL: strings.TrimRight(strings.TrimSpace(baseURL), "/"),
		apiKey:  strings.TrimSpace(apiKey),
		model:   strings.TrimSpace(model),
		client:  &http.Client{Timeout: 120 * time.Second},
		prompt:  defaultOCRPrompt,
		name:    "openai",
	}
}

func (e *OpenAICompatEngine) Name() string { return e.name }

func (e *OpenAICompatEngine) Status() string {
	if e.baseURL == "" || (e.apiKey == "" && !e.allowNoKey) || e.model == "" {
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
	return e.recognizeData(ctx, data, mime, e.prompt)
}

// AllowNoKey explicitly enables an unauthenticated, typically local, endpoint.
func (e *OpenAICompatEngine) AllowNoKey(allow bool) { e.allowNoKey = allow }

// Probe exercises image input without storing homework or exposing the model response.
func (e *OpenAICompatEngine) Probe(ctx context.Context) error {
	if e.Status() != "ok" {
		return fmt.Errorf("请先填写完整的 AI 服务配置")
	}
	picture := image.NewRGBA(image.Rect(0, 0, 64, 64))
	for i := range picture.Pix {
		picture.Pix[i] = 255
	}
	var encoded bytes.Buffer
	if err := png.Encode(&encoded, picture); err != nil {
		return err
	}
	_, err := e.recognizeData(ctx, encoded.Bytes(), "image/png", "这是一次图片输入连接测试，请只回复 OK。")
	return err
}

func (e *OpenAICompatEngine) recognizeData(ctx context.Context, data []byte, mime, prompt string) (string, error) {
	b64 := base64.StdEncoding.EncodeToString(data)

	imgPart := imageURLPart{Type: "image_url"}
	imgPart.ImageURL.URL = "data:" + mime + ";base64," + b64
	body := map[string]any{
		"model":       e.model,
		"temperature": 0,
		"max_tokens":  2048,
		"messages": []chatMessage{{
			Role:    "user",
			Content: []any{textPart{Type: "text", Text: prompt}, imgPart},
		}},
	}
	for key, value := range e.options {
		body[key] = value
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
	if e.apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+e.apiKey)
	}

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
		message := string(raw)
		if e.apiKey != "" {
			message = strings.ReplaceAll(message, e.apiKey, "[已隐藏]")
		}
		return "", fmt.Errorf("OCR 请求失败: HTTP %d: %s", resp.StatusCode, truncate(message, 200))
	}
	var out struct {
		Choices []struct {
			FinishReason string `json:"finish_reason"`
			Message      struct {
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
	if out.Choices[0].FinishReason == "length" {
		return "", fmt.Errorf("%w: 识别结果不完整，请重试", ErrUnavailable)
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
