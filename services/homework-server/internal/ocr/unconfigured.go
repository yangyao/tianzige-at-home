package ocr

import (
	"context"
	"errors"
)

// UnconfiguredEngine keeps original photos readable without inventing homework.
type UnconfiguredEngine struct{}

func NewUnconfigured() *UnconfiguredEngine { return &UnconfiguredEngine{} }
func (*UnconfiguredEngine) Name() string   { return "unconfigured" }
func (*UnconfiguredEngine) Status() string { return "unconfigured" }
func (*UnconfiguredEngine) Recognize(ctx context.Context, _ Image) (string, error) {
	if err := ctx.Err(); err != nil {
		return "", err
	}
	return "", errors.New("还没有设置文字识别，请先看原图")
}
