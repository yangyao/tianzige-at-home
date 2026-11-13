package api

import (
	"context"
	"encoding/json"
	"io"
	"mime"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/yangyao/tianzige-at-home/homework-server/internal/aiconfig"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/i18n"
)

// Provider management is same-origin only, unlike the upload API.
// It must not be possible for another website to replace an endpoint and reuse its key.
func (s *Server) handleAI(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	if origin := r.Header.Get("Origin"); origin != "" {
		u, err := url.Parse(origin)
		scheme := "http"
		if r.TLS != nil {
			scheme = "https"
		}
		if err != nil || u.Host != r.Host || u.Scheme != scheme {
			writeError(w, r, http.StatusForbidden, "same_origin_required", "ai.same_origin_required")
			return
		}
	}
	if r.Header.Get("Sec-Fetch-Site") == "cross-site" {
		writeError(w, r, http.StatusForbidden, "same_origin_required", "ai.same_origin_required")
		return
	}
	if s.ai == nil {
		writeError(w, r, http.StatusServiceUnavailable, "unavailable", "ai.unavailable")
		return
	}
	if r.URL.Path == "/api/settings/ai" && r.Method == http.MethodGet {
		writeJSON(w, http.StatusOK, s.ai.View())
		return
	}
	if (r.URL.Path == "/api/settings/ai" && r.Method != http.MethodPut) ||
		(r.URL.Path == "/api/settings/ai/test" && r.Method != http.MethodPost) {
		methodNotAllowed(w, r)
		return
	}
	mediaType, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || mediaType != "application/json" {
		writeError(w, r, http.StatusUnsupportedMediaType, "bad_request", "ai.json_required")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 16<<10)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	var input aiconfig.Config
	if err := decoder.Decode(&input); err != nil {
		writeError(w, r, http.StatusBadRequest, "bad_request", "ai.invalid_body")
		return
	}
	if decoder.Decode(&struct{}{}) != io.EOF {
		writeError(w, r, http.StatusBadRequest, "bad_request", "ai.single_body")
		return
	}
	if strings.HasSuffix(r.URL.Path, "/test") {
		ctx, cancel := context.WithTimeout(r.Context(), 60*time.Second)
		defer cancel()
		lang := i18n.Lang(r)
		if err := s.ai.Test(ctx, input); err != nil {
			// 上游错误原文不可翻译，只本地化前缀；本地校验错误按原文换成对应语言。
			writeErrorMessage(w, http.StatusBadRequest, "provider_test_failed", i18n.Msgf(lang, "ai.test_failed", i18n.FromSource(lang, err.Error())))
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "message": i18n.Msg(lang, "ai.test_ok")})
		return
	}
	view, err := s.ai.Save(input)
	if err != nil {
		writeErrorMessage(w, http.StatusBadRequest, "invalid_config", i18n.FromSource(i18n.Lang(r), err.Error()))
		return
	}
	writeJSON(w, http.StatusOK, view)
}
