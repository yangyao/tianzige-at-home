package parse

import "context"

// LineParser 是降级实现：OCR 文本按非空行拆成条目，科目一律「其他」。
// 没有任何依赖，OCR 通了就一定能有东西显示。
type LineParser struct{}

func NewLineParser() *LineParser { return &LineParser{} }

func (p *LineParser) Name() string { return "lines" }

func (p *LineParser) Parse(ctx context.Context, ocrText, note string) ([]Group, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	items := CleanItems(SplitLines(ocrText))
	if len(items) == 0 {
		return nil, ErrEmpty
	}
	return []Group{{Subject: "其他", Items: items}}, nil
}
