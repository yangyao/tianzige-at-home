package aiconfig

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/yangyao/tianzige-at-home/homework-server/internal/ocr"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/parse"
)

func testManager(t *testing.T) (*Manager, Config, string) {
	t.Helper()
	c := Config{Profile: "openai", BaseURL: "https://old.example/v1", Model: "vision-old", APIKey: "private-test-key"}
	path := filepath.Join(t.TempDir(), ".private", "ai-provider.json")
	m, err := New(path, c, ocr.NewUnconfigured(), parse.NewLineParser())
	if err != nil {
		t.Fatal(err)
	}
	return m, c, path
}

func TestSavePreservesKeyAndReloadsPrivately(t *testing.T) {
	m, c, path := testManager(t)
	c.APIKey = ""
	c.Model = "vision-new"
	v, err := m.Save(c)
	if err != nil {
		t.Fatal(err)
	}
	raw, _ := json.Marshal(v)
	if strings.Contains(string(raw), "private-test-key") || strings.Contains(string(raw), "\"api_key\"") {
		t.Fatal("secret returned")
	}
	if !v.HasAPIKey {
		t.Fatal("blank input erased key")
	}
	info, _ := os.Stat(path)
	if info.Mode().Perm() != 0600 {
		t.Fatal("unsafe file permission")
	}
	info, _ = os.Stat(filepath.Dir(path))
	if info.Mode().Perm() != 0700 {
		t.Fatal("unsafe directory permission")
	}
	reloaded, err := New(path, Config{}, ocr.NewUnconfigured(), parse.NewLineParser())
	if err != nil || reloaded.View().Model != "vision-new" || !reloaded.View().HasAPIKey {
		t.Fatalf("reload failed: %v", err)
	}
	e, _ := reloaded.Models()
	if e.Status() != "ok" {
		t.Fatal("model not applied")
	}
}

func TestChangingEndpointNeverReusesSecret(t *testing.T) {
	m, c, path := testManager(t)
	c.APIKey = ""
	c.BaseURL = "https://other.example/v1"
	if _, err := m.Save(c); err == nil {
		t.Fatal("saved credential reused on another endpoint")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("invalid update was persisted")
	}
	if m.View().BaseURL != "https://old.example/v1" {
		t.Fatal("invalid update changed active config")
	}
	c.NoAuth = true
	if _, err := m.Save(c); err != nil {
		t.Fatal(err)
	}
	if m.View().HasAPIKey {
		t.Fatal("explicit no-auth retained a key")
	}
	e, _ := m.Models()
	if e.Status() != "ok" {
		t.Fatal("unauthenticated local endpoint not supported")
	}
}

func TestProbeIsUnsavedAndUsesImageInput(t *testing.T) {
	m, c, path := testManager(t)
	called := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		if r.URL.Path != "/v1/chat/completions" || r.Header.Get("Authorization") != "" {
			t.Error("unexpected endpoint or leaked authorization")
		}
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
		}
		raw, _ := json.Marshal(body["messages"])
		if !strings.Contains(string(raw), "data:image/png;base64,") {
			t.Error("probe did not test image input")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"choices":[{"finish_reason":"stop","message":{"content":"OK"}}]}`))
	}))
	defer server.Close()
	c.BaseURL = server.URL + "/v1/chat/completions/"
	c.APIKey = ""
	c.NoAuth = true
	if err := m.Test(context.Background(), c); err != nil {
		t.Fatal(err)
	}
	if !called || m.View().Model != "vision-old" {
		t.Fatal("probe changed active settings")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("probe persisted settings")
	}
}

func TestConcurrentSnapshotsAndSaves(t *testing.T) {
	m, c, _ := testManager(t)
	var wg sync.WaitGroup
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 20; j++ {
				m.View()
				m.Models()
			}
		}()
	}
	for i := 0; i < 5; i++ {
		if _, err := m.Save(c); err != nil {
			t.Fatal(err)
		}
	}
	wg.Wait()
}

func TestInvalidSavedFileIsNotSilentlyIgnored(t *testing.T) {
	_, _, path := testManager(t)
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("{bad-json"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := New(path, Config{}, ocr.NewUnconfigured(), parse.NewLineParser()); err == nil {
		t.Fatal("bad persisted config ignored")
	}
}
