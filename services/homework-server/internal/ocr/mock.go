package ocr

import "context"

// MockEngine 返回固定的中文作业文本，用于无网络环境下的测试与演示。
type MockEngine struct{}

// NewMock 构造离线引擎。
func NewMock() *MockEngine { return &MockEngine{} }

func (m *MockEngine) Name() string   { return "mock" }
func (m *MockEngine) Status() string { return "ok" }

const mockText = `语文：朗读课文《秋天的雨》三遍，家长签字。
数学：练习册 P18 第 1-6 题，口算一页。
英语：跟读 Unit 3 单词表，听录音两遍。`

func (m *MockEngine) Recognize(ctx context.Context, img Image) (string, error) {
	if err := ctx.Err(); err != nil {
		return "", err
	}
	return mockText, nil
}
