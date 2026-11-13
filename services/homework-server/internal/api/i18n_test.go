package api

import (
	"encoding/json"
	"io"
	"net/http"
	"testing"

	"github.com/yangyao/tianzige-at-home/homework-server/internal/parse"
)

// 同一路径分别用中英文请求，message 应随 Accept-Language 变化。
func TestErrorMessagesFollowAcceptLanguage(t *testing.T) {
	env := newTestEnv(t, parse.NewLineParser())

	cases := []struct {
		name string
		path string
		zh   string
		en   string
	}{
		{"批次不存在", "/api/batch/999", "批次不存在", "Batch not found"},
		{"非法日期", "/api/day?date=2026-13-01", "日期格式应为 YYYY-MM-DD", "The date should be YYYY-MM-DD"},
		{"未知接口", "/api/nope", "接口不存在", "No such endpoint"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			for lang, want := range map[string]string{"zh-CN": tc.zh, "en-US": tc.en, "fr-FR": tc.en} {
				req, err := http.NewRequest(http.MethodGet, env.srv.URL+tc.path, nil)
				if err != nil {
					t.Fatal(err)
				}
				req.Header.Set("Accept-Language", lang)
				resp, err := env.srv.Client().Do(req)
				if err != nil {
					t.Fatal(err)
				}
				body, _ := io.ReadAll(resp.Body)
				resp.Body.Close()
				if resp.Header.Get("Vary") != "Accept-Language" {
					t.Fatalf("Vary = %q", resp.Header.Get("Vary"))
				}
				var payload errorPayload
				if err := json.Unmarshal(body, &payload); err != nil {
					t.Fatalf("%s: %v, body=%s", lang, err, body)
				}
				if payload.Error.Message != want {
					t.Fatalf("%s: message = %q, want %q", lang, payload.Error.Message, want)
				}
			}
		})
	}
}
