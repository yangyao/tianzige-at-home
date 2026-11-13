package api

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"github.com/yangyao/tianzige-at-home/homework-server/internal/store"
)

const (
	maxFiles        = 6
	maxFileSize     = 20 << 20
	maxRequestBytes = maxFiles*maxFileSize + 2<<20
	maxNoteRunes    = 500
)

type stagedFile struct {
	tmp  string
	meta store.ImageMeta
}

func (s *Server) handleIngest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, r)
		return
	}
	ctx := r.Context()
	r.Body = http.MaxBytesReader(w, r.Body, maxRequestBytes)
	if err := r.ParseMultipartForm(16 << 20); err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			writeError(w, r, http.StatusRequestEntityTooLarge, "file_too_large", "err.file_too_large")
			return
		}
		writeErrorf(w, r, http.StatusBadRequest, "bad_request", "err.upload_parse", err.Error())
		return
	}
	defer func() {
		if r.MultipartForm != nil {
			r.MultipartForm.RemoveAll()
		}
	}()

	files := r.MultipartForm.File["files"]
	switch {
	case len(files) == 0:
		writeError(w, r, http.StatusBadRequest, "bad_request", "err.no_files")
		return
	case len(files) > maxFiles:
		writeErrorf(w, r, http.StatusBadRequest, "too_many_files", "err.too_many_files", maxFiles)
		return
	}

	note := strings.TrimSpace(r.FormValue("note"))
	if utf8.RuneCountInString(note) > maxNoteRunes {
		writeErrorf(w, r, http.StatusBadRequest, "bad_request", "err.note_too_long", maxNoteRunes)
		return
	}

	date := strings.TrimSpace(r.FormValue("date"))
	if date == "" {
		date = store.Today()
	} else if !store.ValidDate(date) {
		writeError(w, r, http.StatusBadRequest, "invalid_date", "err.invalid_date_format")
		return
	}

	staged, apiErr := s.stageFiles(files)
	if apiErr != nil {
		removeTemps(staged)
		writeError(w, r, apiErr.status, apiErr.code, apiErr.msgKey)
		return
	}

	shas := make([]string, len(staged))
	for i := range staged {
		shas[i] = staged[i].meta.SHA256
	}
	dupID, dup, err := s.st.FindBatchByImages(ctx, shas)
	if err != nil {
		removeTemps(staged)
		s.internal(w, r, err)
		return
	}
	if dup {
		removeTemps(staged)
		existing, err := s.st.GetBatch(ctx, dupID)
		if err != nil {
			s.internal(w, r, err)
			return
		}
		s.logger.Printf("软去重命中: 批次 %d", dupID)
		writeJSON(w, http.StatusAccepted, ingestResponse{
			BatchID:     dupID,
			Status:      existing.Status,
			Date:        existing.Date,
			ImageCount:  len(existing.Images),
			DuplicateOf: &dupID,
		})
		return
	}

	metas := make([]store.ImageMeta, len(staged))
	for i := range staged {
		metas[i] = staged[i].meta
	}
	batchID, err := s.st.CreateBatch(ctx, date, note, metas)
	if err != nil {
		removeTemps(staged)
		s.internal(w, r, err)
		return
	}

	batch, err := s.st.GetBatch(ctx, batchID)
	if err != nil {
		// 刚落库就查不到，属于严重异常，回滚记录。
		if _, delErr := s.st.DeleteBatch(ctx, batchID); delErr != nil {
			s.logger.Printf("回滚批次 %d 失败: %v", batchID, delErr)
		}
		removeTemps(staged)
		s.internal(w, r, err)
		return
	}
	if err := s.moveIntoPlace(staged, batch); err != nil {
		if _, delErr := s.st.DeleteBatch(ctx, batchID); delErr != nil {
			s.logger.Printf("回滚批次 %d 失败: %v", batchID, delErr)
		}
		removeTemps(staged)
		removeBatchFiles(s.dataDir, batch)
		s.internal(w, r, err)
		return
	}

	s.pl.Enqueue(batchID)
	s.logger.Printf("收到批次 %d：%d 张图，日期 %s", batchID, len(staged), date)
	writeJSON(w, http.StatusAccepted, ingestResponse{
		BatchID:    batchID,
		Status:     store.StatusPending,
		Date:       date,
		ImageCount: len(staged),
	})
}

type httpError struct {
	status int
	code   string
	msgKey string
}

// stageFiles 把每个上传文件写到 dataDir/tmp，同时算 sha256、嗅探类型、读宽高。
func (s *Server) stageFiles(files []*multipart.FileHeader) ([]stagedFile, *httpError) {
	tmpDir := filepath.Join(s.dataDir, "tmp")
	staged := make([]stagedFile, 0, len(files))
	for idx, fh := range files {
		if fh.Size > maxFileSize {
			return staged, &httpError{http.StatusRequestEntityTooLarge, "file_too_large", "err.file_too_large"}
		}
		src, err := fh.Open()
		if err != nil {
			return staged, &httpError{http.StatusBadRequest, "bad_request", "err.read_upload"}
		}
		head := make([]byte, 512)
		n, _ := io.ReadFull(src, head)
		ext, ok := detectExt(head[:n], fh.Filename)
		if !ok {
			src.Close()
			return staged, &httpError{http.StatusUnsupportedMediaType, "unsupported_type", "err.unsupported_type"}
		}

		tmp, err := os.CreateTemp(tmpDir, fmt.Sprintf("ingest-%d-*.part", idx))
		if err != nil {
			src.Close()
			return staged, &httpError{http.StatusInternalServerError, "internal", "err.temp_file"}
		}
		hasher := sha256.New()
		size, err := io.Copy(io.MultiWriter(tmp, hasher), io.LimitReader(io.MultiReader(bytes.NewReader(head[:n]), src), maxFileSize+1))
		src.Close()
		if closeErr := tmp.Close(); err == nil {
			err = closeErr
		}
		if err != nil {
			os.Remove(tmp.Name())
			return staged, &httpError{http.StatusBadRequest, "bad_request", "err.save_upload"}
		}
		if size > maxFileSize {
			os.Remove(tmp.Name())
			return staged, &httpError{http.StatusRequestEntityTooLarge, "file_too_large", "err.file_too_large"}
		}
		w, h := imageDims(tmp.Name())
		staged = append(staged, stagedFile{
			tmp: tmp.Name(),
			meta: store.ImageMeta{
				Ext:    ext,
				SHA256: hex.EncodeToString(hasher.Sum(nil)),
				Width:  w,
				Height: h,
			},
		})
	}
	return staged, nil
}

// moveIntoPlace 把临时文件挪到 {date}/{batch_id}_{n}.{ext}。
func (s *Server) moveIntoPlace(staged []stagedFile, batch *store.Batch) error {
	if len(batch.Images) != len(staged) {
		return fmt.Errorf("图片数量不一致: %d vs %d", len(batch.Images), len(staged))
	}
	for i := range staged {
		dest := filepath.Join(s.dataDir, filepath.FromSlash(batch.Images[i].Path))
		if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
			return err
		}
		if err := os.Rename(staged[i].tmp, dest); err != nil {
			return err
		}
		staged[i].tmp = "" // 已挪走，不要再清理
	}
	return nil
}

func removeTemps(staged []stagedFile) {
	for _, f := range staged {
		if f.tmp != "" {
			os.Remove(f.tmp)
		}
	}
}

func removeBatchFiles(dataDir string, batch *store.Batch) {
	for _, img := range batch.Images {
		os.Remove(filepath.Join(dataDir, filepath.FromSlash(img.Path)))
	}
}

// detectExt 先按内容嗅探，再退回文件扩展名；两者都不认就拒绝。
func detectExt(head []byte, filename string) (string, bool) {
	switch http.DetectContentType(head) {
	case "image/jpeg":
		return "jpg", true
	case "image/png":
		return "png", true
	case "image/webp":
		return "webp", true
	}
	if isHEIC(head) {
		return "heic", true
	}
	switch strings.ToLower(filepath.Ext(filename)) {
	case ".jpg", ".jpeg":
		return "jpg", true
	case ".png":
		return "png", true
	case ".webp":
		return "webp", true
	case ".heic", ".heif":
		return "heic", true
	}
	return "", false
}

// isHEIC 判断 ISO-BMFF 的 ftyp box 是否是 HEIC/HEIF 品牌。
func isHEIC(head []byte) bool {
	if len(head) < 12 || string(head[4:8]) != "ftyp" {
		return false
	}
	brand := string(head[8:12])
	switch brand {
	case "heic", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs", "mif1", "msf1":
		return true
	}
	return false
}
