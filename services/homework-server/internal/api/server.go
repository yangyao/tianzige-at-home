// Package api 是 HTTP 层：路由、参数校验、错误码、CORS、静态文件。
// 只做接入与呈现，识别逻辑全在 pipeline 里。
package api

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/yangyao/tianzige-at-home/homework-server/internal/aiconfig"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/i18n"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/pipeline"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/store"
)

// Options 是构造 Server 的可选项。
type Options struct {
	DataDir string
	WebDir  string // 空表示不挂静态站点
	Version string
}

// Server 聚合依赖并实现 http.Handler。
type Server struct {
	st      *store.Store
	pl      *pipeline.Pipeline
	dataDir string
	webDir  string
	version string
	logger  *log.Logger
	ocr     func() string
	ai      *aiconfig.Manager
}

// New 构造 HTTP handler。
func New(st *store.Store, pl *pipeline.Pipeline, opt Options, logger *log.Logger) *Server {
	return &Server{
		st:      st,
		pl:      pl,
		dataDir: opt.DataDir,
		webDir:  opt.WebDir,
		version: opt.Version,
		logger:  logger,
		ocr:     func() string { return "unconfigured" },
	}
}

// SetOCRStatus 注入 OCR 引擎健康状态（main 里传入 engine.Status）。
func (s *Server) SetOCRStatus(f func() string) {
	if f != nil {
		s.ocr = f
	}
}

func (s *Server) SetAI(manager *aiconfig.Manager) { s.ai = manager }

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// 错误文案随 Accept-Language 变化，代理/CDN 必须按语言分键缓存。
	w.Header().Add("Vary", "Accept-Language")
	if r.URL.Path == "/api/settings/ai" || r.URL.Path == "/api/settings/ai/test" {
		s.handleAI(w, r)
		return
	}
	setCORS(w)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}

	path := r.URL.Path
	switch {
	case path == "/api/health":
		s.handleHealth(w, r)
	case path == "/api/ingest":
		s.handleIngest(w, r)
	case path == "/api/batches":
		s.handleListBatches(w, r)
	case strings.HasPrefix(path, "/api/batch/"):
		s.handleBatch(w, r)
	case path == "/api/day":
		s.handleDay(w, r)
	case path == "/api/days":
		s.handleDays(w, r)
	case strings.HasPrefix(path, "/img/"):
		s.handleImage(w, r)
	default:
		s.handleStatic(w, r)
	}
}

func setCORS(w http.ResponseWriter) {
	h := w.Header()
	h.Set("Access-Control-Allow-Origin", "*")
	h.Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
	h.Set("Access-Control-Allow-Headers", "Content-Type")
	h.Set("Access-Control-Max-Age", "86400")
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, r)
		return
	}
	dbState := "ok"
	if err := s.st.Ping(r.Context()); err != nil {
		dbState = "error"
	}
	writeJSON(w, http.StatusOK, healthResponse{
		OK:      dbState == "ok",
		Version: s.version,
		Time:    store.FormatTime(store.Now()),
		DB:      dbState,
		OCR:     s.ocr(),
	})
}

func (s *Server) handleBatch(w http.ResponseWriter, r *http.Request) {
	rest := strings.TrimPrefix(r.URL.Path, "/api/batch/")
	parts := strings.Split(strings.Trim(rest, "/"), "/")
	if len(parts) == 0 || parts[0] == "" {
		writeNotFound(w, r, "err.batch_not_found")
		return
	}
	id, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil || id < 1 {
		writeNotFound(w, r, "err.batch_not_found")
		return
	}

	switch {
	case len(parts) == 1:
		switch r.Method {
		case http.MethodGet:
			s.getBatch(w, r, id)
		case http.MethodDelete:
			s.deleteBatch(w, r, id)
		default:
			methodNotAllowed(w, r)
		}
	case len(parts) == 2 && parts[1] == "rerun":
		if r.Method != http.MethodPost {
			methodNotAllowed(w, r)
			return
		}
		s.rerunBatch(w, r, id)
	default:
		writeNotFound(w, r, "err.api_not_found")
	}
}

// handleStatic 挂载 -web 指定的目录到根路径。
func (s *Server) handleStatic(w http.ResponseWriter, r *http.Request) {
	if s.webDir == "" {
		writeNotFound(w, r, "err.api_not_found")
		return
	}
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		methodNotAllowed(w, r)
		return
	}
	// 交给 FileServer 做目录索引与路径清理；webDir 是用户显式指定的目录。
	if r.URL.Path == "/" {
		http.Redirect(w, r, "upload.html", http.StatusFound)
		return
	}
	http.FileServer(http.Dir(s.webDir)).ServeHTTP(w, r)
}

// ---------- 通用响应 ----------

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		// 此时响应头已发出，只能记录。
		_ = err
	}
}

func writeError(w http.ResponseWriter, r *http.Request, status int, code, msgKey string) {
	writeErrorMessage(w, status, code, i18n.Msg(i18n.Lang(r), msgKey))
}

// writeErrorf 是带参数的版本，用于含数量的文案。
func writeErrorf(w http.ResponseWriter, r *http.Request, status int, code, msgKey string, args ...any) {
	writeErrorMessage(w, status, code, i18n.Msgf(i18n.Lang(r), msgKey, args...))
}

// writeErrorMessage 直接写出已本地化的 message，用于上游错误原文。
func writeErrorMessage(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, errorPayload{Error: errorBody{Code: code, Message: message}})
}

func methodNotAllowed(w http.ResponseWriter, r *http.Request) {
	writeError(w, r, http.StatusMethodNotAllowed, "bad_request", "err.method_not_allowed")
}

func writeNotFound(w http.ResponseWriter, r *http.Request, msgKey string) {
	writeError(w, r, http.StatusNotFound, "not_found", msgKey)
}

func (s *Server) internal(w http.ResponseWriter, r *http.Request, err error) {
	s.logger.Printf("内部错误: %v", err)
	writeError(w, r, http.StatusInternalServerError, "internal", "err.internal")
}

// ---------- 参数 ----------

// dateParam 解析 YYYY-MM-DD 查询参数，缺省返回上海时区今天。
func dateParam(r *http.Request) (string, error) {
	raw := strings.TrimSpace(r.URL.Query().Get("date"))
	if raw == "" {
		return store.Today(), nil
	}
	if !store.ValidDate(raw) {
		return "", errInvalidDate
	}
	return raw, nil
}

var errInvalidDate = errors.New("invalid_date")

func (s *Server) handleImage(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		methodNotAllowed(w, r)
		return
	}
	rest := strings.TrimPrefix(r.URL.Path, "/img/")
	parts := strings.Split(rest, "/")
	if len(parts) != 2 {
		writeNotFound(w, r, "err.image_not_found")
		return
	}
	date, name := parts[0], parts[1]
	if !store.ValidDate(date) || !safeName(name) {
		writeNotFound(w, r, "err.image_not_found")
		return
	}
	root := filepath.Clean(s.dataDir)
	full := filepath.Join(root, date, name)
	if !strings.HasPrefix(full, root+string(os.PathSeparator)) {
		writeNotFound(w, r, "err.image_not_found")
		return
	}
	f, err := os.Open(full)
	if err != nil {
		writeNotFound(w, r, "err.image_not_found")
		return
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || info.IsDir() {
		writeNotFound(w, r, "err.image_not_found")
		return
	}
	if ct := contentTypeByName(name); ct != "" {
		w.Header().Set("Content-Type", ct)
	}
	http.ServeContent(w, r, name, info.ModTime(), f)
}

// safeName 只允许单段文件名，杜绝 ../ 与绝对路径。
func safeName(name string) bool {
	if name == "" || name == "." || name == ".." {
		return false
	}
	if strings.ContainsAny(name, `/\`) || strings.ContainsRune(name, 0) {
		return false
	}
	return true
}

func contentTypeByName(name string) string {
	switch strings.ToLower(filepath.Ext(name)) {
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".png":
		return "image/png"
	case ".webp":
		return "image/webp"
	case ".heic", ".heif":
		return "image/heic"
	default:
		return ""
	}
}
