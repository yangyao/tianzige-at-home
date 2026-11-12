package api

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/yangyao/tianzige-at-home/homework-server/internal/aiconfig"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/ocr"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/parse"
)

func aiServer(t *testing.T) *Server {
	t.Helper()
	m, err := aiconfig.New(filepath.Join(t.TempDir(), ".private", "ai.json"),
		aiconfig.Config{Profile: "zai", BaseURL: "https://api.z.ai/api/coding/paas/v4", Model: "glm-5.3-flash", APIKey: "do-not-return-this-secret"},
		ocr.NewUnconfigured(), parse.NewLineParser())
	if err != nil {
		t.Fatal(err)
	}
	s := New(nil, nil, Options{}, log.New(io.Discard, "", 0))
	s.SetAI(m)
	return s
}

func TestAISettingsNeverReturnSavedSecret(t *testing.T) {
	s := aiServer(t)
	r := httptest.NewRequest(http.MethodGet, "http://nas.local/api/settings/ai", nil)
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	if w.Code != 200 || strings.Contains(w.Body.String(), "do-not-return") || strings.Contains(w.Body.String(), "\"api_key\"") {
		t.Fatal("settings leaked secret or failed")
	}
	if w.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("settings may be cached")
	}
	var v aiconfig.View
	json.Unmarshal(w.Body.Bytes(), &v)
	if !v.HasAPIKey || v.Model != "glm-5.3-flash" {
		t.Fatal(v)
	}
}

func TestAISettingsRejectCrossOriginAndSimpleForms(t *testing.T) {
	s := aiServer(t)
	for _, test := range []struct {
		origin, contentType, body string
		status                    int
	}{
		{"http://evil.example", "application/json", `{}`, 403},
		{"null", "application/json", `{}`, 403},
		{"http://nas.local", "text/plain", `{}`, 415},
		{"http://nas.local", "application/json", `{} {}`, 400},
		{"http://nas.local", "application/json", `{"unknown":"field"}`, 400},
	} {
		r := httptest.NewRequest(http.MethodPut, "http://nas.local/api/settings/ai", strings.NewReader(test.body))
		r.Header.Set("Origin", test.origin)
		r.Header.Set("Content-Type", test.contentType)
		w := httptest.NewRecorder()
		s.ServeHTTP(w, r)
		if w.Code != test.status {
			t.Fatalf("origin %q got %d want %d", test.origin, w.Code, test.status)
		}
		if w.Header().Get("Access-Control-Allow-Origin") != "" {
			t.Fatal("provider settings allow cross-origin access")
		}
	}
}

func TestAISettingsSaveAppliesWithoutRestart(t *testing.T) {
	s := aiServer(t)
	body := `{"profile":"openai","base_url":"http://127.0.0.1:10000/v1","model":"local-vision","api_key":"","no_auth":true}`
	r := httptest.NewRequest(http.MethodPut, "http://nas.local/api/settings/ai", strings.NewReader(body))
	r.Header.Set("Origin", "http://nas.local")
	r.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	if w.Code != 200 {
		t.Fatalf("%d: %s", w.Code, w.Body.String())
	}
	e, p := s.ai.Models()
	if e.Name() != "openai" || e.Status() != "ok" || p.Name() != "openai" {
		t.Fatal("new configuration not applied")
	}
}
