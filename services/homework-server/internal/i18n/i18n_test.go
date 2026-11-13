package i18n

import (
	"net/http/httptest"
	"strings"
	"testing"
)

func TestLang(t *testing.T) {
	cases := []struct {
		header string
		want   string
	}{
		{"zh-CN", LangZh},
		{"zh-TW", LangZh},
		{"zh", LangZh},
		{"zh-CN,zh;q=0.9,en;q=0.8", LangZh},
		{"en-US", LangEn},
		{"en-US,en;q=0.9", LangEn},
		{"fr", LangEn},
		{"fr-FR,fr;q=0.9", LangEn},
		{"", LangEn},
		{"*", LangEn},
		{"  zh-Hans  ", LangZh},
	}
	for _, tc := range cases {
		r := httptest.NewRequest("GET", "/api/health", nil)
		if tc.header != "" {
			r.Header.Set("Accept-Language", tc.header)
		}
		if got := Lang(r); got != tc.want {
			t.Errorf("Lang(%q) = %q, want %q", tc.header, got, tc.want)
		}
	}
	if got := Lang(nil); got != LangEn {
		t.Errorf("Lang(nil) = %q, want %q", got, LangEn)
	}
}

func TestMsgUnknownKeyReturnsKey(t *testing.T) {
	if got := Msg(LangZh, "no.such.key"); got != "no.such.key" {
		t.Errorf("Msg unknown = %q", got)
	}
	if got := Msgf(LangEn, "no.such.key", 1, 2); got != "no.such.key" {
		t.Errorf("Msgf unknown = %q", got)
	}
}

func TestMsgfFormats(t *testing.T) {
	zh := Msgf(LangZh, "err.too_many_files", 6)
	en := Msgf(LangEn, "err.too_many_files", 6)
	if !strings.Contains(zh, "6") || !strings.Contains(zh, "张") {
		t.Errorf("zh = %q", zh)
	}
	if !strings.Contains(en, "6") || !strings.Contains(strings.ToLower(en), "photos") {
		t.Errorf("en = %q", en)
	}
}

func TestFromSource(t *testing.T) {
	if got := FromSource(LangEn, "请填写模型名称（最多 200 字节）"); got != "Enter a model name (up to 200 bytes)" {
		t.Errorf("known source = %q", got)
	}
	const upstream = "dial tcp 10.0.0.1:443: connection refused"
	if got := FromSource(LangEn, upstream); got != upstream {
		t.Errorf("unknown source = %q", got)
	}
}

// 每个 key 两种语言都必须有非空文案；sources 必须指向存在的 key。
func TestMessagesComplete(t *testing.T) {
	for key, e := range messages {
		if strings.TrimSpace(e.zh) == "" {
			t.Errorf("key %q: empty zh", key)
		}
		if strings.TrimSpace(e.en) == "" {
			t.Errorf("key %q: empty en", key)
		}
		if e.zh == e.en {
			t.Errorf("key %q: zh and en are identical (%q)", key, e.zh)
		}
	}
	for source, key := range sources {
		if _, ok := messages[key]; !ok {
			t.Errorf("source %q points to missing key %q", source, key)
		}
	}
}
