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
			writeError(w, http.StatusForbidden, "same_origin_required", "请从 NAS 上传页打开 AI 设置")
			return
		}
	}
	if r.Header.Get("Sec-Fetch-Site") == "cross-site" {
		writeError(w, http.StatusForbidden, "same_origin_required", "请从 NAS 上传页打开 AI 设置")
		return
	}
	if s.ai == nil {
		writeError(w, http.StatusServiceUnavailable, "unavailable", "AI 设置暂不可用")
		return
	}
	if r.URL.Path == "/api/settings/ai" && r.Method == http.MethodGet {
		writeJSON(w, http.StatusOK, s.ai.View())
		return
	}
	if (r.URL.Path == "/api/settings/ai" && r.Method != http.MethodPut) ||
		(r.URL.Path == "/api/settings/ai/test" && r.Method != http.MethodPost) {
		methodNotAllowed(w)
		return
	}
	mediaType, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || mediaType != "application/json" {
		writeError(w, http.StatusUnsupportedMediaType, "bad_request", "请使用 JSON 提交设置")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 16<<10)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	var input aiconfig.Config
	if err := decoder.Decode(&input); err != nil {
		writeError(w, http.StatusBadRequest, "bad_request", "AI 设置格式不正确或内容过长")
		return
	}
	if decoder.Decode(&struct{}{}) != io.EOF {
		writeError(w, http.StatusBadRequest, "bad_request", "只能提交一组 AI 设置")
		return
	}
	if strings.HasSuffix(r.URL.Path, "/test") {
		ctx, cancel := context.WithTimeout(r.Context(), 60*time.Second)
		defer cancel()
		if err := s.ai.Test(ctx, input); err != nil {
			writeError(w, http.StatusBadRequest, "provider_test_failed", err.Error())
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "message": "连接成功，模型接受了图片请求。测试没有修改已保存的配置。"})
		return
	}
	view, err := s.ai.Save(input)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_config", err.Error())
		return
	}
	writeJSON(w, http.StatusOK, view)
}
