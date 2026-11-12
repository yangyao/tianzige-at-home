package api

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"io"
	"log"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/yangyao/tianzige-at-home/homework-server/internal/ocr"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/parse"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/pipeline"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/store"
)

type testEnv struct {
	srv *httptest.Server
	st  *store.Store
	pl  *pipeline.Pipeline
	dir string
}

func newTestEnv(t *testing.T, parser parse.Parser) *testEnv {
	t.Helper()
	dir := t.TempDir()
	st, err := store.Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	lg := log.New(io.Discard, "", 0)
	pl := pipeline.New(st, ocr.NewMock(), parser, lg)
	srv := httptest.NewServer(New(st, pl, Options{DataDir: dir, Version: "test"}, lg))
	t.Cleanup(func() {
		srv.Close()
		pl.Stop()
		st.Close()
	})
	return &testEnv{srv: srv, st: st, pl: pl, dir: dir}
}

func (e *testEnv) process(t *testing.T, id int64) {
	t.Helper()
	if err := e.pl.ProcessOnce(context.Background(), id); err != nil {
		t.Fatalf("ProcessOnce(%d): %v", id, err)
	}
}

func (e *testEnv) request(t *testing.T, method, path string, body io.Reader, contentType string) *http.Response {
	t.Helper()
	req, err := http.NewRequest(method, e.srv.URL+path, body)
	if err != nil {
		t.Fatal(err)
	}
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	resp, err := e.srv.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

func decode[T any](t *testing.T, resp *http.Response, wantStatus int) T {
	t.Helper()
	defer resp.Body.Close()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != wantStatus {
		t.Fatalf("%s %s -> %d, want %d, body=%s", resp.Request.Method, resp.Request.URL.Path, resp.StatusCode, wantStatus, raw)
	}
	var v T
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatalf("解析响应失败: %v, body=%s", err, raw)
	}
	return v
}

type filePart struct {
	name string
	data []byte
}

func (e *testEnv) ingest(t *testing.T, fields map[string]string, files []filePart) *http.Response {
	t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	for k, v := range fields {
		if err := mw.WriteField(k, v); err != nil {
			t.Fatal(err)
		}
	}
	for _, f := range files {
		fw, err := mw.CreateFormFile("files", f.name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := fw.Write(f.data); err != nil {
			t.Fatal(err)
		}
	}
	if err := mw.Close(); err != nil {
		t.Fatal(err)
	}
	return e.request(t, http.MethodPost, "/api/ingest", &buf, mw.FormDataContentType())
}

func pngBytes(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for x := 0; x < w; x++ {
		for y := 0; y < h; y++ {
			img.Set(x, y, color.RGBA{R: uint8(x), G: uint8(y), B: 100, A: 255})
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestIngestProcessDayAndImage(t *testing.T) {
	env := newTestEnv(t, parse.NewLineParser())
	date := store.Today()
	photo := pngBytes(t, 100, 40)

	resp := decode[ingestResponse](t, env.ingest(t, map[string]string{"note": "今天作业", "date": date},
		[]filePart{{name: "a.png", data: photo}}), http.StatusAccepted)
	if resp.BatchID == 0 || resp.Status != store.StatusPending || resp.Date != date || resp.ImageCount != 1 {
		t.Fatalf("ingest = %+v", resp)
	}
	if resp.DuplicateOf != nil {
		t.Fatal("首次上传不应是重复")
	}

	// 识别前：有图没字，state=pending。
	day := decode[dayView](t, env.request(t, http.MethodGet, "/api/day?date="+date, nil, ""), http.StatusOK)
	if day.State != statePending || len(day.Images) != 1 || len(day.Subjects) != 0 {
		t.Fatalf("pending 视图 = %+v", day)
	}
	if !day.IsToday || day.DaysAgo != 0 {
		t.Fatalf("is_today=%v days_ago=%d", day.IsToday, day.DaysAgo)
	}
	if day.Images[0].Width != 100 || day.Images[0].Height != 40 {
		t.Fatalf("宽高 = %dx%d", day.Images[0].Width, day.Images[0].Height)
	}

	env.process(t, resp.BatchID)

	day = decode[dayView](t, env.request(t, http.MethodGet, "/api/day?date="+date, nil, ""), http.StatusOK)
	if day.State != stateReady {
		t.Fatalf("state = %s", day.State)
	}
	if len(day.Subjects) != 1 || day.Subjects[0].Subject != "其他" {
		t.Fatalf("subjects = %+v", day.Subjects)
	}
	if len(day.Subjects[0].Items) != 3 {
		t.Fatalf("items = %+v", day.Subjects[0].Items)
	}
	if day.Subjects[0].ImageURL == nil || *day.Subjects[0].ImageURL != "/img/"+date+"/1_1.png" {
		t.Fatalf("image_url = %v", day.Subjects[0].ImageURL)
	}
	if day.Note == nil || *day.Note != "今天作业" {
		t.Fatalf("note = %v", day.Note)
	}
	if day.Subjects[0].Items[0].Done {
		t.Fatal("MVP 下 done 应为 false")
	}

	// 批次详情：图片带 OCR 原文。
	detail := decode[batchDetail](t, env.request(t, http.MethodGet, "/api/batch/1", nil, ""), http.StatusOK)
	if detail.Status != store.StatusDone || len(detail.Images) != 1 || detail.Images[0].OCR == nil {
		t.Fatalf("detail = %+v", detail)
	}

	// 原图可读，字节一致。
	imgResp := env.request(t, http.MethodGet, day.Images[0].URL, nil, "")
	got, _ := io.ReadAll(imgResp.Body)
	imgResp.Body.Close()
	if imgResp.StatusCode != 200 || !bytes.Equal(got, photo) {
		t.Fatalf("图片读取失败: status=%d len=%d", imgResp.StatusCode, len(got))
	}
	if ct := imgResp.Header.Get("Content-Type"); ct != "image/png" {
		t.Fatalf("Content-Type = %q", ct)
	}

	// 同一张图再传一次：软去重，不新建批次。
	dup := decode[ingestResponse](t, env.ingest(t, map[string]string{"date": date},
		[]filePart{{name: "a.png", data: photo}}), http.StatusAccepted)
	if dup.DuplicateOf == nil || *dup.DuplicateOf != resp.BatchID || dup.BatchID != resp.BatchID {
		t.Fatalf("去重响应 = %+v", dup)
	}
	list := decode[batchesResponse](t, env.request(t, http.MethodGet, "/api/batches", nil, ""), http.StatusOK)
	if len(list.Batches) != 1 {
		t.Fatalf("重复上传后批次数 = %d", len(list.Batches))
	}
	if list.Batches[0].ItemCount != 3 || list.Batches[0].ImageCount != 1 {
		t.Fatalf("摘要计数 = %+v", list.Batches[0])
	}
}

type orderParser struct{}

func (orderParser) Name() string { return "order-fake" }

func (orderParser) Parse(ctx context.Context, text, note string) ([]parse.Group, error) {
	return []parse.Group{
		{Subject: "数学", Items: []string{"数学：练习册 P18 第 1-6 题，口算一页。"}},
		{Subject: "历史", Items: []string{"背朝代歌"}},
		{Subject: "语文", Items: []string{"朗读课文"}},
	}, nil
}

func TestDaySubjectOrderingAndMultiBatch(t *testing.T) {
	env := newTestEnv(t, orderParser{})
	date := store.Today()

	a := decode[ingestResponse](t, env.ingest(t, map[string]string{"date": date},
		[]filePart{{name: "1.png", data: pngBytes(t, 20, 20)}}), http.StatusAccepted)
	b := decode[ingestResponse](t, env.ingest(t, map[string]string{"date": date},
		[]filePart{{name: "2.png", data: pngBytes(t, 30, 30)}}), http.StatusAccepted)
	if a.BatchID == b.BatchID {
		t.Fatal("不同图片应生成不同批次")
	}
	env.process(t, a.BatchID)
	// b 还没处理，day 应为 pending。
	day := decode[dayView](t, env.request(t, http.MethodGet, "/api/day?date="+date, nil, ""), http.StatusOK)
	if day.State != statePending || len(day.Images) != 2 || len(day.Subjects) != 0 {
		t.Fatalf("混合状态 = %s imgs=%d subj=%d", day.State, len(day.Images), len(day.Subjects))
	}
	env.process(t, b.BatchID)

	day = decode[dayView](t, env.request(t, http.MethodGet, "/api/day?date="+date, nil, ""), http.StatusOK)
	if day.State != stateReady || len(day.Images) != 2 || len(day.BatchIDs) != 2 {
		t.Fatalf("day = %+v", day)
	}
	subjects := []string{}
	for _, g := range day.Subjects {
		subjects = append(subjects, g.Subject)
	}
	want := []string{"语文", "数学", "历史"}
	if strings.Join(subjects, ",") != strings.Join(want, ",") {
		t.Fatalf("科目顺序 = %v, want %v", subjects, want)
	}
	if len(day.Subjects[0].Items) != 2 || len(day.Subjects[1].Items) != 2 {
		t.Fatalf("跨批次合并失败: %+v", day.Subjects)
	}
	// 数学条目文字出现在第一张图的 OCR 里，image_url 应指向它。
	if day.Subjects[1].ImageURL == nil || !strings.HasSuffix(*day.Subjects[1].ImageURL, "/"+date+"/1_1.png") {
		t.Fatalf("数学 image_url = %v", day.Subjects[1].ImageURL)
	}
	// 历史条目文字不在图里，但该批次只有一张图，回退到唯一来源图。
	if day.Subjects[2].ImageURL == nil {
		t.Fatal("单图批次应回填 image_url")
	}
}

func TestDaysFillsGaps(t *testing.T) {
	env := newTestEnv(t, parse.NewLineParser())
	date := store.Today()
	r := decode[ingestResponse](t, env.ingest(t, map[string]string{"date": date},
		[]filePart{{name: "a.png", data: pngBytes(t, 10, 10)}}), http.StatusAccepted)
	env.process(t, r.BatchID)

	from := time.Now().In(store.Location()).AddDate(0, 0, -5).Format(store.DateLayout)
	got := decode[daysResponse](t, env.request(t, http.MethodGet, "/api/days?from="+from+"&to="+date, nil, ""), http.StatusOK)
	if len(got.Days) != 6 {
		t.Fatalf("天数 = %d, want 6: %+v", len(got.Days), got.Days)
	}
	for i, d := range got.Days {
		if i < 5 && (d.Has || d.ItemCount != 0) {
			t.Fatalf("空位未补齐: %+v", d)
		}
		if i > 0 && d.Date <= got.Days[i-1].Date {
			t.Fatalf("未按升序: %s", d.Date)
		}
	}
	last := got.Days[5]
	if last.Date != date || !last.Has || last.ItemCount != 3 {
		t.Fatalf("今天 = %+v", last)
	}
}

func TestRerunKeepsCheckinAndDelete(t *testing.T) {
	env := newTestEnv(t, parse.NewLineParser())
	date := store.Today()
	r := decode[ingestResponse](t, env.ingest(t, map[string]string{"date": date},
		[]filePart{{name: "a.png", data: pngBytes(t, 12, 12)}}), http.StatusAccepted)
	env.process(t, r.BatchID)

	content := "数学：练习册 P18 第 1-6 题，口算一页。"
	if err := env.st.SetCheckin(context.Background(), "其他", content, true); err != nil {
		t.Fatal(err)
	}

	rr := decode[rerunResponse](t, env.request(t, http.MethodPost, "/api/batch/1/rerun", nil, ""), http.StatusAccepted)
	if rr.ID != r.BatchID || rr.Status != store.StatusPending {
		t.Fatalf("rerun = %+v", rr)
	}
	// 进行中的 rerun 再调一次：202 但忽略。
	again := decode[rerunResponse](t, env.request(t, http.MethodPost, "/api/batch/1/rerun", nil, ""), http.StatusAccepted)
	if again.Status != store.StatusPending {
		t.Fatalf("幂等 rerun = %+v", again)
	}
	env.process(t, r.BatchID)

	detail := decode[batchDetail](t, env.request(t, http.MethodGet, "/api/batch/1", nil, ""), http.StatusOK)
	var found bool
	for _, g := range detail.Subjects {
		for _, it := range g.Items {
			if it.Content == content {
				found = true
				if !it.Done || it.DoneAt == nil {
					t.Fatalf("checkin 丢失: %+v", it)
				}
			}
		}
	}
	if !found {
		t.Fatal("rerun 后条目缺失")
	}

	// 删除：记录 + 磁盘文件都没了。
	resp := env.request(t, http.MethodDelete, "/api/batch/1", nil, "")
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("delete status = %d", resp.StatusCode)
	}
	if _, err := os.Stat(filepath.Join(env.dir, date, "1_1.png")); !os.IsNotExist(err) {
		t.Fatalf("图片未删除: %v", err)
	}
	notFound := decode[errorPayload](t, env.request(t, http.MethodGet, "/api/batch/1", nil, ""), http.StatusNotFound)
	if notFound.Error.Code != "not_found" || notFound.Error.Message == "" {
		t.Fatalf("错误体 = %+v", notFound)
	}
	day := decode[dayView](t, env.request(t, http.MethodGet, "/api/day?date="+date, nil, ""), http.StatusOK)
	if day.State != stateEmpty || len(day.Images) != 0 || len(day.Subjects) != 0 {
		t.Fatalf("删除后 = %+v", day)
	}
}

func TestErrorCodes(t *testing.T) {
	env := newTestEnv(t, parse.NewLineParser())
	date := store.Today()
	png := pngBytes(t, 8, 8)

	cases := []struct {
		name   string
		method string
		path   string
		body   func() (*bytes.Buffer, string)
		status int
		code   string
	}{
		{name: "非法日期", method: "GET", path: "/api/day?date=2026-13-01", status: 400, code: "invalid_date"},
		{name: "days 缺参数", method: "GET", path: "/api/days?from=" + date, status: 400, code: "bad_request"},
		{name: "days 区间过大", method: "GET", path: "/api/days?from=2026-01-01&to=2026-03-10", status: 400, code: "bad_request"},
		{name: "days 倒序", method: "GET", path: "/api/days?from=2026-03-10&to=2026-01-01", status: 400, code: "bad_request"},
		{name: "批次不存在", method: "GET", path: "/api/batch/999", status: 404, code: "not_found"},
		{name: "rerun 不存在", method: "POST", path: "/api/batch/999/rerun", status: 404, code: "not_found"},
		{name: "删除不存在", method: "DELETE", path: "/api/batch/999", status: 404, code: "not_found"},
		{name: "limit 非数字", method: "GET", path: "/api/batches?limit=x", status: 400, code: "bad_request"},
		{name: "batches 非法日期", method: "GET", path: "/api/batches?date=x", status: 400, code: "invalid_date"},
		{name: "路径穿越", method: "GET", path: "/img/../hw.db", status: 404, code: "not_found"},
		{name: "未知接口", method: "GET", path: "/api/nope", status: 404, code: "not_found"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := env.request(t, tc.method, tc.path, nil, "")
			got := decode[errorPayload](t, req, tc.status)
			if got.Error.Code != tc.code || got.Error.Message == "" {
				t.Fatalf("错误体 = %+v, want code %s", got, tc.code)
			}
		})
	}

	t.Run("无文件", func(t *testing.T) {
		got := decode[errorPayload](t, env.ingest(t, map[string]string{"date": date}, nil), 400)
		if got.Error.Code != "bad_request" {
			t.Fatalf("code = %s", got.Error.Code)
		}
	})
	t.Run("超过 6 张", func(t *testing.T) {
		files := make([]filePart, 7)
		for i := range files {
			files[i] = filePart{name: "x.png", data: png}
		}
		got := decode[errorPayload](t, env.ingest(t, map[string]string{"date": date}, files), 400)
		if got.Error.Code != "too_many_files" {
			t.Fatalf("code = %s", got.Error.Code)
		}
	})
	t.Run("格式不支持", func(t *testing.T) {
		got := decode[errorPayload](t, env.ingest(t, map[string]string{"date": date},
			[]filePart{{name: "note.txt", data: []byte("hello")}}), 415)
		if got.Error.Code != "unsupported_type" {
			t.Fatalf("code = %s", got.Error.Code)
		}
	})
	t.Run("单张超过 20MB", func(t *testing.T) {
		big := make([]byte, maxFileSize+1)
		copy(big, pngHeader())
		got := decode[errorPayload](t, env.ingest(t, map[string]string{"date": date},
			[]filePart{{name: "big.jpg", data: big}}), 413)
		if got.Error.Code != "file_too_large" {
			t.Fatalf("code = %s", got.Error.Code)
		}
	})
	t.Run("备注过长", func(t *testing.T) {
		got := decode[errorPayload](t, env.ingest(t, map[string]string{"note": strings.Repeat("长", 501)},
			[]filePart{{name: "a.png", data: png}}), 400)
		if got.Error.Code != "bad_request" {
			t.Fatalf("code = %s", got.Error.Code)
		}
	})
	t.Run("上传日期非法", func(t *testing.T) {
		got := decode[errorPayload](t, env.ingest(t, map[string]string{"date": "2026/01/01"},
			[]filePart{{name: "a.png", data: png}}), 400)
		if got.Error.Code != "invalid_date" {
			t.Fatalf("code = %s", got.Error.Code)
		}
	})
}

func pngHeader() []byte {
	return []byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'}
}

func TestHealthAndCORS(t *testing.T) {
	env := newTestEnv(t, parse.NewLineParser())
	h := decode[healthResponse](t, env.request(t, http.MethodGet, "/api/health", nil, ""), http.StatusOK)
	if !h.OK || h.DB != "ok" || h.Version != "test" || h.OCR != "unconfigured" {
		t.Fatalf("health = %+v", h)
	}
	if !strings.HasSuffix(h.Time, "+08:00") {
		t.Fatalf("health.time = %s", h.Time)
	}

	resp := env.request(t, http.MethodOptions, "/api/day", nil, "")
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("OPTIONS = %d", resp.StatusCode)
	}
	if resp.Header.Get("Access-Control-Allow-Origin") != "*" {
		t.Fatalf("CORS 头缺失: %v", resp.Header)
	}

	getResp := env.request(t, http.MethodGet, "/api/batches", nil, "")
	getResp.Body.Close()
	if getResp.Header.Get("Access-Control-Allow-Origin") != "*" {
		t.Fatal("GET 也应带 CORS 头")
	}
}

func TestMultiImageBatchMapsSubjectToSourceImage(t *testing.T) {
	env := newTestEnv(t, parse.NewLineParser())
	date := store.Today()
	r := decode[ingestResponse](t, env.ingest(t, map[string]string{"date": date}, []filePart{
		{name: "1.png", data: pngBytes(t, 10, 10)},
		{name: "2.png", data: pngBytes(t, 11, 11)},
	}), http.StatusAccepted)
	if r.ImageCount != 2 {
		t.Fatalf("image_count = %d", r.ImageCount)
	}
	env.process(t, r.BatchID)
	day := decode[dayView](t, env.request(t, http.MethodGet, "/api/day?date="+date, nil, ""), http.StatusOK)
	if day.State != stateReady || len(day.Images) != 2 {
		t.Fatalf("day = %+v", day)
	}
	if len(day.Subjects) != 1 || day.Subjects[0].ImageURL == nil {
		t.Fatalf("多图批次应回填 image_url: %+v", day.Subjects)
	}
	if !strings.HasSuffix(*day.Subjects[0].ImageURL, "/1_1.png") {
		t.Fatalf("image_url = %s", *day.Subjects[0].ImageURL)
	}
}
