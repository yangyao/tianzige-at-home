package api

import (
	"net/http"
	"sort"
	"strings"

	"github.com/yangyao/tianzige-at-home/homework-server/internal/parse"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/store"
)

// 三种呈现状态，电视端只认这三个值。
const (
	stateEmpty   = "empty"
	statePending = "pending"
	stateReady   = "ready"
)

func (s *Server) handleDay(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	date, err := dateParam(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_date", "日期格式应为 YYYY-MM-DD")
		return
	}
	batches, err := s.st.BatchesByDate(r.Context(), date)
	if err != nil {
		s.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, buildDayView(date, batches))
}

func (s *Server) handleDays(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	q := r.URL.Query()
	from := strings.TrimSpace(q.Get("from"))
	to := strings.TrimSpace(q.Get("to"))
	if from == "" || to == "" {
		writeError(w, http.StatusBadRequest, "bad_request", "from 与 to 都是必填参数")
		return
	}
	if !store.ValidDate(from) || !store.ValidDate(to) {
		writeError(w, http.StatusBadRequest, "invalid_date", "日期格式应为 YYYY-MM-DD")
		return
	}
	span, err := daysBetween(from, to)
	if err != nil {
		writeError(w, http.StatusBadRequest, "bad_request", "结束日期不能早于开始日期")
		return
	}
	if span > 62 {
		writeError(w, http.StatusBadRequest, "bad_request", "一次最多查询 62 天")
		return
	}
	marks, err := s.st.DayMarks(r.Context(), from, to)
	if err != nil {
		s.internal(w, err)
		return
	}
	byDate := make(map[string]store.DayMark, len(marks))
	for _, m := range marks {
		byDate[m.Date] = m
	}

	days := make([]dayMark, 0, span)
	start, _ := store.ParseDate(from)
	for i := 0; i < span; i++ {
		d := start.AddDate(0, 0, i).Format(store.DateLayout)
		m := byDate[d]
		days = append(days, dayMark{Date: d, Has: m.Has, ItemCount: m.ItemCount})
	}
	writeJSON(w, http.StatusOK, daysResponse{Days: days})
}

// daysBetween 返回 [from,to] 的天数（含首尾）。
func daysBetween(from, to string) (int, error) {
	f, err := store.ParseDate(from)
	if err != nil {
		return 0, err
	}
	t, err := store.ParseDate(to)
	if err != nil {
		return 0, err
	}
	if t.Before(f) {
		return 0, errInvalidDate
	}
	return int(t.Sub(f).Hours()/24) + 1, nil
}

// buildDayView 聚合一天的全部批次。
//
// 状态判定（协议只允许三个值）：
//   - 没有任何批次 → empty
//   - 还有 pending/ocr/parsing 的批次 → pending（有图，正在识别）
//   - 全部批次都结束且至少一个 done → ready
//   - 全部失败（没有可用文字）→ pending（客户端退化成只看图，提示「正在识别」，
//     比显示「今天没有作业」安全）
func buildDayView(date string, batches []store.Batch) dayView {
	v := dayView{
		Date:     date,
		IsToday:  date == store.Today(),
		State:    stateEmpty,
		Images:   []imageDTO{},
		Subjects: []subjectGroup{},
		BatchIDs: []int64{},
	}
	if n, err := store.DaysAgo(date, store.Today()); err == nil {
		v.DaysAgo = n
	}
	if len(batches) == 0 {
		return v
	}

	inFlight := false
	anyDone := false
	notes := []string{}
	pathByImage := map[int64]string{}
	for _, b := range batches {
		v.BatchIDs = append(v.BatchIDs, b.ID)
		if n := strings.TrimSpace(b.Note); n != "" {
			notes = append(notes, n)
		}
		switch b.Status {
		case store.StatusPending, store.StatusOCR, store.StatusParsing:
			inFlight = true
		case store.StatusDone:
			anyDone = true
		}
		for _, img := range b.Images {
			v.Images = append(v.Images, imageDTO{
				ID:     img.ID,
				URL:    "/img/" + img.Path,
				Width:  img.Width,
				Height: img.Height,
			})
			pathByImage[img.ID] = img.Path
		}
	}

	switch {
	case inFlight:
		v.State = statePending
	case anyDone:
		v.State = stateReady
	default:
		v.State = statePending
	}
	if len(notes) > 0 {
		joined := strings.Join(notes, "\n")
		v.Note = &joined
	}
	if v.State != stateReady {
		return v
	}

	// 只取 done 批次的条目；同一科目跨批次合并，按批次创建顺序 + 批内 sort。
	groups := map[string][]itemDTO{}
	groupOrder := []string{}
	groupImage := map[string]int64{}
	for _, b := range batches {
		if b.Status != store.StatusDone {
			continue
		}
		for _, it := range b.Items {
			if _, ok := groups[it.Subject]; !ok {
				groupOrder = append(groupOrder, it.Subject)
			}
			dto := itemDTO{ID: it.ID, Content: it.Content, Done: it.Done, DoneAt: strPtr(it.DoneAt)}
			groups[it.Subject] = append(groups[it.Subject], dto)
			if _, seen := groupImage[it.Subject]; !seen && it.ImageID > 0 {
				groupImage[it.Subject] = it.ImageID
			}
		}
	}
	sort.SliceStable(groupOrder, func(i, j int) bool {
		return parse.Order(groupOrder[i]) < parse.Order(groupOrder[j])
	})
	for _, subj := range groupOrder {
		var url *string
		if id := groupImage[subj]; id > 0 {
			if p, ok := pathByImage[id]; ok {
				u := "/img/" + p
				url = &u
			}
		}
		v.Subjects = append(v.Subjects, subjectGroup{Subject: subj, Items: groups[subj], ImageURL: url})
	}
	return v
}

// batchToDetail 把 store.Batch 转成 openapi 的 BatchDetail。
func batchToDetail(b *store.Batch) batchDetail {
	d := batchDetail{
		ID:        b.ID,
		Date:      b.Date,
		CreatedAt: b.CreatedAt,
		Status:    b.Status,
		Note:      strPtr(b.Note),
		Error:     strPtr(b.Error),
		Images:    make([]imageDTO, 0, len(b.Images)),
		Subjects:  []subjectGroup{},
	}
	for _, img := range b.Images {
		d.Images = append(d.Images, imageDTO{
			ID:     img.ID,
			URL:    "/img/" + img.Path,
			Width:  img.Width,
			Height: img.Height,
			OCR:    strPtr(img.OCRRaw),
		})
	}
	d.Subjects = groupItems(b.Items, b.Images)
	return d
}

// groupItems 把一个批次的 item 按科目分组并排序。
func groupItems(items []store.Item, images []store.Image) []subjectGroup {
	pathByImage := map[int64]string{}
	for _, img := range images {
		pathByImage[img.ID] = img.Path
	}
	groups := map[string][]itemDTO{}
	order := []string{}
	groupImage := map[string]int64{}
	for _, it := range items {
		if _, ok := groups[it.Subject]; !ok {
			order = append(order, it.Subject)
		}
		groups[it.Subject] = append(groups[it.Subject], itemDTO{
			ID: it.ID, Content: it.Content, Done: it.Done, DoneAt: strPtr(it.DoneAt),
		})
		if _, seen := groupImage[it.Subject]; !seen && it.ImageID > 0 {
			groupImage[it.Subject] = it.ImageID
		}
	}
	sort.SliceStable(order, func(i, j int) bool {
		return parse.Order(order[i]) < parse.Order(order[j])
	})
	out := make([]subjectGroup, 0, len(order))
	for _, subj := range order {
		var url *string
		if id := groupImage[subj]; id > 0 {
			if p, ok := pathByImage[id]; ok {
				u := "/img/" + p
				url = &u
			}
		}
		out = append(out, subjectGroup{Subject: subj, Items: groups[subj], ImageURL: url})
	}
	return out
}
