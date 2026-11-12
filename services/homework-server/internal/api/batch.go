package api

import (
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/yangyao/tianzige-at-home/homework-server/internal/store"
)

func (s *Server) handleListBatches(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	q := r.URL.Query()
	limit := 6
	if raw := strings.TrimSpace(q.Get("limit")); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil {
			writeError(w, http.StatusBadRequest, "bad_request", "limit 应为 1–50 的整数")
			return
		}
		if n < 1 {
			n = 1
		}
		if n > 50 {
			n = 50
		}
		limit = n
	}
	date := strings.TrimSpace(q.Get("date"))
	if date != "" && !store.ValidDate(date) {
		writeError(w, http.StatusBadRequest, "invalid_date", "日期格式应为 YYYY-MM-DD")
		return
	}

	sums, err := s.st.ListBatches(r.Context(), limit, date)
	if err != nil {
		s.internal(w, err)
		return
	}
	out := make([]batchSummary, 0, len(sums))
	for _, sum := range sums {
		out = append(out, batchSummary{
			ID:         sum.ID,
			Date:       sum.Date,
			CreatedAt:  sum.CreatedAt,
			Status:     sum.Status,
			ImageCount: sum.ImageCount,
			ItemCount:  sum.ItemCount,
			Note:       strPtr(sum.Note),
			Error:      strPtr(sum.Error),
		})
	}
	writeJSON(w, http.StatusOK, batchesResponse{Batches: out})
}

func (s *Server) getBatch(w http.ResponseWriter, r *http.Request, id int64) {
	b, err := s.st.GetBatch(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		writeNotFound(w, "批次不存在")
		return
	}
	if err != nil {
		s.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, batchToDetail(b))
}

func (s *Server) deleteBatch(w http.ResponseWriter, r *http.Request, id int64) {
	paths, err := s.st.DeleteBatch(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		writeNotFound(w, "批次不存在")
		return
	}
	if err != nil {
		s.internal(w, err)
		return
	}
	root := filepath.Clean(s.dataDir)
	for _, p := range paths {
		full := filepath.Join(root, filepath.FromSlash(p))
		if !strings.HasPrefix(full, root+string(os.PathSeparator)) {
			continue
		}
		if err := os.Remove(full); err != nil && !os.IsNotExist(err) {
			s.logger.Printf("删除图片 %s 失败: %v", full, err)
		}
	}
	s.logger.Printf("已删除批次 %d", id)
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) rerunBatch(w http.ResponseWriter, r *http.Request, id int64) {
	b, err := s.st.GetBatch(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		writeNotFound(w, "批次不存在")
		return
	}
	if err != nil {
		s.internal(w, err)
		return
	}

	switch b.Status {
	case store.StatusPending, store.StatusOCR, store.StatusParsing:
		// 正在处理中，幂等返回当前状态，不重复入队。
		writeJSON(w, http.StatusAccepted, rerunResponse{ID: id, Status: b.Status})
		return
	}

	if err := s.st.ReplaceItems(r.Context(), id, nil); err != nil {
		s.internal(w, err)
		return
	}
	if err := s.st.ClearOCR(r.Context(), id); err != nil {
		s.internal(w, err)
		return
	}
	if err := s.st.UpdateStatus(r.Context(), id, store.StatusPending, ""); err != nil {
		s.internal(w, err)
		return
	}
	s.pl.Enqueue(id)
	s.logger.Printf("批次 %d 重新入队", id)
	writeJSON(w, http.StatusAccepted, rerunResponse{ID: id, Status: store.StatusPending})
}
