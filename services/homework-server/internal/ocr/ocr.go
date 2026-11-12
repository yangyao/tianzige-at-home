// Package ocr 是 OCR 适配层：一个接口，两个实现（离线 mock / OpenAI 兼容 vision API）。
package ocr

import (
	"context"
	"errors"
)

// ErrUnavailable 表示 OCR 服务暂时不可用（网络错误、5xx、429）。
var ErrUnavailable = errors.New("OCR 服务暂时不可用")

// Image 是一次识别的输入。
type Image struct {
	Path string // 绝对路径
	MIME string // image/jpeg 等
}

// Engine 把一张图片变成文字。
type Engine interface {
	Name() string
	// Status 用于 /api/health：ok / unavailable / unconfigured。
	Status() string
	Recognize(ctx context.Context, img Image) (string, error)
}
