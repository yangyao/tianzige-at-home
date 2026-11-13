// Package i18n 提供服务端错误文案的本地化：
// 按 Accept-Language 只区分中文与英文，其余语言一律回退英文。
package i18n

import (
	"fmt"
	"net/http"
	"strings"
)

// 支持的语言标识。其他语言统一归 LangEn。
const (
	LangZh = "zh"
	LangEn = "en"
)

// Lang 解析 Accept-Language：取第一个语言标签，以 zh 开头返回 zh，否则 en。
// 缺省、空值、通配符都回退 en。
func Lang(r *http.Request) string {
	if r == nil {
		return LangEn
	}
	raw := r.Header.Get("Accept-Language")
	if raw == "" {
		return LangEn
	}
	first := raw
	if i := strings.IndexByte(first, ','); i >= 0 {
		first = first[:i]
	}
	if i := strings.IndexByte(first, ';'); i >= 0 {
		first = first[:i]
	}
	first = strings.ToLower(strings.TrimSpace(first))
	if strings.HasPrefix(first, "zh") {
		return LangZh
	}
	return LangEn
}

// Msg 按 key 取文案。未知 key 原样返回 key 本身，便于发现遗漏。
func Msg(lang, key string) string {
	e, ok := messages[key]
	if !ok {
		return key
	}
	if lang == LangZh {
		return e.zh
	}
	return e.en
}

// Msgf 取文案并按参数格式化；未知 key 不做格式化，直接返回 key。
func Msgf(lang, key string, args ...any) string {
	e, ok := messages[key]
	if !ok {
		return key
	}
	format := e.en
	if lang == LangZh {
		format = e.zh
	}
	if len(args) == 0 {
		return format
	}
	return fmt.Sprintf(format, args...)
}

// FromSource 把上游（aiconfig 等）返回的中文错误原文换成对应语言的文案。
// 认不出的原文原样返回——那类内容（网络错误、上游模型错误）本身不可翻译。
func FromSource(lang, source string) string {
	key, ok := sources[source]
	if !ok {
		return source
	}
	return Msg(lang, key)
}
