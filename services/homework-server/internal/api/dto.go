package api

// 响应体 DTO。字段名与 spec/openapi.yaml 一一对应（snake_case），
// 可空字段用指针 + omitempty 输出 null / 省略。

type errorPayload struct {
	Error errorBody `json:"error"`
}

type errorBody struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type healthResponse struct {
	OK      bool   `json:"ok"`
	Version string `json:"version"`
	Time    string `json:"time"`
	DB      string `json:"db"`
	OCR     string `json:"ocr"`
}

type ingestResponse struct {
	BatchID     int64  `json:"batch_id"`
	Status      string `json:"status"`
	Date        string `json:"date"`
	ImageCount  int    `json:"image_count"`
	DuplicateOf *int64 `json:"duplicate_of,omitempty"`
}

type batchSummary struct {
	ID         int64   `json:"id"`
	Date       string  `json:"date"`
	CreatedAt  string  `json:"created_at"`
	Status     string  `json:"status"`
	ImageCount int     `json:"image_count"`
	ItemCount  int     `json:"item_count"`
	Note       *string `json:"note"`
	Error      *string `json:"error"`
}

type batchDetail struct {
	ID        int64          `json:"id"`
	Date      string         `json:"date"`
	CreatedAt string         `json:"created_at"`
	Status    string         `json:"status"`
	Note      *string        `json:"note"`
	Error     *string        `json:"error"`
	Images    []imageDTO     `json:"images"`
	Subjects  []subjectGroup `json:"subjects"`
}

type imageDTO struct {
	ID     int64   `json:"id"`
	URL    string  `json:"url"`
	Width  int     `json:"width"`
	Height int     `json:"height"`
	OCR    *string `json:"ocr,omitempty"`
}

type itemDTO struct {
	ID      int64   `json:"id"`
	Content string  `json:"content"`
	Done    bool    `json:"done"`
	DoneAt  *string `json:"done_at,omitempty"`
}

type subjectGroup struct {
	Subject  string    `json:"subject"`
	Items    []itemDTO `json:"items"`
	ImageURL *string   `json:"image_url"`
}

type dayView struct {
	Date     string         `json:"date"`
	IsToday  bool           `json:"is_today"`
	DaysAgo  int            `json:"days_ago"`
	State    string         `json:"state"`
	Note     *string        `json:"note"`
	Images   []imageDTO     `json:"images"`
	Subjects []subjectGroup `json:"subjects"`
	BatchIDs []int64        `json:"batch_ids"`
}

type dayMark struct {
	Date      string `json:"date"`
	Has       bool   `json:"has"`
	ItemCount int    `json:"item_count"`
}

type daysResponse struct {
	Days []dayMark `json:"days"`
}

type batchesResponse struct {
	Batches []batchSummary `json:"batches"`
}

type rerunResponse struct {
	ID     int64  `json:"id"`
	Status string `json:"status"`
}

func strPtr(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
