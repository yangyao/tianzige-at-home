package aiconfig

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

func TestProbeRedactsProviderEchoBeforeTruncation(t *testing.T) {
	m, c, _ := testManager(t)
	c.APIKey = strings.Repeat("private-credential-", 20)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		w.Write([]byte(strings.Repeat("x", 190) + c.APIKey))
	}))
	defer server.Close()
	c.BaseURL = server.URL
	err := m.Test(context.Background(), c)
	if err == nil || strings.Contains(err.Error(), "private-") {
		t.Fatal("provider error leaked credential text")
	}
}

func TestFailedSaveKeepsActiveProvider(t *testing.T) {
	m, c, path := testManager(t)
	if err := os.MkdirAll(path, 0700); err != nil {
		t.Fatal(err)
	}
	oldEngine, oldParser := m.Models()
	c.Model = "new-vision"
	if _, err := m.Save(c); err == nil {
		t.Fatal("expected persistence failure")
	}
	e, p := m.Models()
	if e != oldEngine || p != oldParser || m.View().Model != "vision-old" {
		t.Fatal("failed save changed active provider")
	}
}
