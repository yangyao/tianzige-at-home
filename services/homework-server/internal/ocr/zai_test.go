package ocr

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestZAIUsesConfiguredEndpointAndVisionPayload(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/coding/paas/v4/chat/completions" {
			t.Errorf("wrong endpoint: %s", r.URL.Path)
		}
		if r.Header.Get("Authorization") != "Bearer test-key" {
			t.Error("missing authentication")
		}
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
		}
		if body["model"] != "glm-5.3-flash" || body["max_tokens"] != float64(16384) {
			t.Errorf("wrong model parameters: %v", body)
		}
		if body["thinking"].(map[string]any)["type"] != "enabled" {
			t.Error("thinking not enabled")
		}
		raw, _ := json.Marshal(body["messages"])
		if !strings.Contains(string(raw), "data:image/jpeg;base64,dGVzdC1pbWFnZQ==") {
			t.Error("missing original image")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"choices":[{"finish_reason":"stop","message":{"content":"语文：订正练习 P31"}}]}`))
	}))
	defer server.Close()
	path := filepath.Join(t.TempDir(), "photo.jpg")
	if err := os.WriteFile(path, []byte("test-image"), 0600); err != nil {
		t.Fatal(err)
	}
	e := NewZAI(server.URL+"/api/coding/paas/v4", "test-key", "glm-5.3-flash")
	text, err := e.Recognize(context.Background(), Image{Path: path, MIME: "image/jpeg"})
	if err != nil || text != "语文：订正练习 P31" {
		t.Fatalf("%q %v", text, err)
	}
}

func TestZAIRejectsTruncatedOutputAndNeverFallsBack(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"choices":[{"finish_reason":"length","message":{"content":"不完整的作业"}}]}`))
	}))
	defer server.Close()
	path := filepath.Join(t.TempDir(), "photo.jpg")
	if err := os.WriteFile(path, []byte("test"), 0600); err != nil {
		t.Fatal(err)
	}
	e := NewZAI(server.URL, "test-key", "glm-5.3-flash")
	text, err := e.Recognize(context.Background(), Image{Path: path, MIME: "image/jpeg"})
	if err == nil || text != "" || calls != 1 {
		t.Fatalf("partial result or fallback: %q %v %d", text, err, calls)
	}
}
