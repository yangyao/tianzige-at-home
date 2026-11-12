// Package parse 把 OCR 全文拆成「科目 + 条目」。
// 两个实现：LLMParser（主力）与 LineParser（降级，永远可用）。
package parse

import (
	"context"
	"errors"
	"strings"
)

// ErrUnavailable 表示分科服务不可用。
var ErrUnavailable = errors.New("分科服务暂时不可用")

// ErrEmpty 表示没有解析出任何条目。
var ErrEmpty = errors.New("没有识别出作业条目")

// Group 是一个科目的作业条目。
type Group struct {
	Subject string
	Items   []string
}

// Parser 把 OCR 全文 + 老师备注拆成分科结果。
type Parser interface {
	Name() string
	Parse(ctx context.Context, ocrText, note string) ([]Group, error)
}

// 固定科目顺序，与 openapi.yaml 的 Subject 说明一致。
var subjectOrder = map[string]int{
	"语文": 0,
	"数学": 1,
	"英语": 2,
	"科学": 3,
	"道法": 4,
	"其他": 5,
}

// Order 返回科目排序权重，未知科目排在所有已知科目之后，彼此保持原始顺序。
func Order(subject string) int {
	if n, ok := subjectOrder[subject]; ok {
		return n
	}
	return 6
}

// NormalizeSubject 清理科目名：去空白、去常见后缀；空则归入「其他」。
func NormalizeSubject(s string) string {
	s = strings.TrimSpace(s)
	s = strings.TrimSuffix(s, "课")
	s = strings.TrimSuffix(s, "作业")
	s = strings.Trim(s, "：:·。 ")
	switch s {
	case "", "其它", "未知":
		return "其他"
	case "道德与法治", "道德":
		return "道法"
	case "English":
		return "英语"
	}
	return s
}

// CleanItems 去掉空白条目与完全重复的条目，保持顺序。
func CleanItems(items []string) []string {
	out := make([]string, 0, len(items))
	seen := map[string]bool{}
	for _, it := range items {
		it = strings.TrimSpace(it)
		it = strings.TrimLeft(it, "·•-*—– ") // 去掉列表符号
		it = strings.TrimSpace(it)
		if it == "" || seen[it] || isPageMarker(it) {
			continue
		}
		seen[it] = true
		out = append(out, it)
	}
	return out
}

// isPageMarker 跳过流水线插入的分页标记「【第 N 页】」。
func isPageMarker(s string) bool {
	return strings.HasPrefix(s, "【第") && strings.HasSuffix(s, "页】")
}

// SplitLines 按行拆分 OCR 文本，兼容 \r\n。
func SplitLines(text string) []string {
	text = strings.ReplaceAll(text, "\r\n", "\n")
	text = strings.ReplaceAll(text, "\r", "\n")
	return strings.Split(text, "\n")
}
