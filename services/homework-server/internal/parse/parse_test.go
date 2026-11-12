package parse

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestLineParserSplitsAndDedupes(t *testing.T) {
	p := NewLineParser()
	groups, err := p.Parse(context.Background(), "  数学：练习册 P18\n\n口算一页\r\n口算一页\n· 听写单词  ", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(groups) != 1 || groups[0].Subject != "其他" {
		t.Fatalf("groups = %+v", groups)
	}
	want := []string{"数学：练习册 P18", "口算一页", "听写单词"}
	if len(groups[0].Items) != len(want) {
		t.Fatalf("items = %#v", groups[0].Items)
	}
	for i, w := range want {
		if groups[0].Items[i] != w {
			t.Fatalf("items[%d] = %q, want %q", i, groups[0].Items[i], w)
		}
	}
	if _, err := p.Parse(context.Background(), "  \n\t\n", ""); err != ErrEmpty {
		t.Fatalf("空文本应返回 ErrEmpty, got %v", err)
	}
}

func TestSubjectOrderAndNormalize(t *testing.T) {
	order := []string{"语文", "数学", "英语", "科学", "道法", "其他"}
	for i, s := range order {
		if Order(s) != i {
			t.Fatalf("Order(%q) = %d", s, Order(s))
		}
	}
	if Order("历史") != 6 {
		t.Fatal("未知科目应排最后")
	}
	cases := map[string]string{
		" 语文 ":  "语文",
		"数学课":   "数学",
		"英语作业":  "英语",
		"道德与法治": "道法",
		"":      "其他",
		"其它":    "其他",
	}
	for in, want := range cases {
		if got := NormalizeSubject(in); got != want {
			t.Fatalf("NormalizeSubject(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestDecodeGroups(t *testing.T) {
	text := "好的，结果如下：\n```json\n[{\"subject\":\"数学\",\"items\":[\"练习册 P18\"]},{\"subject\":\"语文\",\"items\":[\"  \",\"朗读\"]},{\"subject\":\"科学\",\"items\":[]}]\n```"
	groups, err := decodeGroups(text)
	if err != nil {
		t.Fatal(err)
	}
	if len(groups) != 2 {
		t.Fatalf("groups = %+v", groups)
	}
	if groups[0].Subject != "数学" || groups[1].Subject != "语文" {
		t.Fatalf("subjects = %+v", groups)
	}
	if _, err := decodeGroups("抱歉我不能完成"); err == nil {
		t.Fatal("没有 JSON 应报错")
	}
	if _, err := decodeGroups("[{\"subject\":\"语文\",\"items\":[]}]"); err == nil {
		t.Fatal("空条目应报错")
	}
}

func TestLLMParserRetryOnce(t *testing.T) {
	var calls int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/chat/completions" {
			t.Errorf("path = %s", r.URL.Path)
		}
		var body struct {
			Temperature float64 `json:"temperature"`
		}
		json.NewDecoder(r.Body).Decode(&body)
		if body.Temperature != 0 {
			t.Errorf("temperature = %v", body.Temperature)
		}
		calls++
		content := "这不是 JSON"
		if calls > 1 {
			content = "[{\"subject\":\"数学\",\"items\":[\"练习册 P18\"]}]"
		}
		payload, _ := json.Marshal(map[string]any{
			"choices": []map[string]any{{"message": map[string]string{"content": content}}},
		})
		w.Header().Set("Content-Type", "application/json")
		w.Write(payload)
	}))
	defer srv.Close()

	p := NewLLMParser(srv.URL, "k", "m")
	groups, err := p.Parse(context.Background(), "数学：练习册 P18", "今天是数学")
	if err != nil {
		t.Fatal(err)
	}
	if calls != 2 {
		t.Fatalf("应重试一次, calls = %d", calls)
	}
	if len(groups) != 1 || groups[0].Subject != "数学" || groups[0].Items[0] != "练习册 P18" {
		t.Fatalf("groups = %+v", groups)
	}

	p2 := NewLLMParser("", "", "")
	if _, err := p2.Parse(context.Background(), "x", ""); err == nil || !strings.Contains(err.Error(), "未配置") {
		t.Fatalf("未配置应立刻失败: %v", err)
	}
}
