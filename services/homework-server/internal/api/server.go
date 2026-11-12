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

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
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
		methodNotAllowed(w)
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
		writeNotFound(w, "批次不存在")
		return
	}
	id, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil || id < 1 {
		writeNotFound(w, "批次不存在")
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
			methodNotAllowed(w)
		}
	case len(parts) == 2 && parts[1] == "rerun":
		if r.Method != http.MethodPost {
			methodNotAllowed(w)
			return
		}
		s.rerunBatch(w, r, id)
	default:
		writeNotFound(w, "接口不存在")
	}
}

// handleStatic 挂载 -web 指定的目录到根路径。
func (s *Server) handleStatic(w http.ResponseWriter, r *http.Request) {
	if s.webDir == "" {
		writeNotFound(w, "接口不存在")
		return
	}
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		methodNotAllowed(w)
		return
	}
	// 交给 FileServer 做目录索引与路径清理；webDir 是用户显式指定的目录。
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

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, errorPayload{Error: errorBody{Code: code, Message: message}})
}

func methodNotAllowed(w http.ResponseWriter) {
	writeError(w, http.StatusMethodNotAllowed, "bad_request", "请求方法不支持")
}

func writeNotFound(w http.ResponseWriter, message string) {
	writeError(w, http.StatusNotFound, "not_found", message)
}

func (s *Server) internal(w http.ResponseWriter, err error) {
	s.logger.Printf("内部错误: %v", err)
	writeError(w, http.StatusInternalServerError, "internal", "服务内部错误，请查看服务端日志")
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
		methodNotAllowed(w)
		return
	}
	rest := strings.TrimPrefix(r.URL.Path, "/img/")
	parts := strings.Split(rest, "/")
	if len(parts) != 2 {
		writeNotFound(w, "图片不存在")
		return
	}
	date, name := parts[0], parts[1]
	if !store.ValidDate(date) || !safeName(name) {
		writeNotFound(w, "图片不存在")
		return
	}
	root := filepath.Clean(s.dataDir)
	full := filepath.Join(root, date, name)
	if !strings.HasPrefix(full, root+string(os.PathSeparator)) {
		writeNotFound(w, "图片不存在")
		return
	}
	f, err := os.Open(full)
	if err != nil {
		writeNotFound(w, "图片不存在")
		return
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || info.IsDir() {
		writeNotFound(w, "图片不存在")
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
