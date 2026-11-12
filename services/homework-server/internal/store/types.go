package store

import "time"

// 批次状态，取值必须与 openapi.yaml 的 BatchStatus 一致。
const (
	StatusPending = "pending"
	StatusOCR     = "ocr"
	StatusParsing = "parsing"
	StatusDone    = "done"
	StatusFailed  = "failed"
)

// ImageMeta 是入库前的一张图片元数据。path 由 CreateBatch 生成：
// {date}/{batch_id}_{序号}.{ext}
type ImageMeta struct {
	Ext    string
	SHA256 string
	Width  int
	Height int
}

// Image 是 image 表的一行。
type Image struct {
	ID      int64
	BatchID int64
	Path    string
	SHA256  string
	Width   int
	Height  int
	OCRRaw  string
	OCRAt   string
}

// Item 是 item 表的一行，Done/DoneAt 来自 checkin 表（用户数据，rerun 不丢）。
type Item struct {
	ID      int64
	BatchID int64
	ImageID int64 // 0 表示 null
	Subject string
	Content string
	Sort    int
	Done    bool
	DoneAt  string
}

// Batch 是 batch 表的一行，附带所属图片与条目。
type Batch struct {
	ID        int64
	Date      string
	Note      string
	Status    string
	Error     string
	CreatedAt string
	Images    []Image
	Items     []Item
}

// NewItem 是 rerun 重建时写入的条目。
type NewItem struct {
	ImageID int64 // 0 表示 null
	Subject string
	Content string
	Sort    int
}

// DayMark 是某天是否有作业的统计。
type DayMark struct {
	Date      string
	Has       bool
	ItemCount int
}

// CreatedAt 返回创建时间的 time.Time 视图，解析失败时返回零值。
func (b Batch) CreatedTime() time.Time {
	t, err := time.Parse(dateTimeLayout, b.CreatedAt)
	if err != nil {
		return time.Time{}
	}
	return t
}
