// Package pipeline 是识别流水线：pending → ocr → parsing → done / failed。
// 单 worker 串行处理，避免并发写库与并发调用模型。
package pipeline

import (
	"context"
	"errors"
	"fmt"
	"log"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/yangyao/tianzige-at-home/homework-server/internal/ocr"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/parse"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/store"
)

// Pipeline 串行消费批次队列。
type Pipeline struct {
	st     *store.Store
	engine ocr.Engine
	parser parse.Parser
	logger *log.Logger

	queue chan int64
	stop  chan struct{}
	done  chan struct{}
	once  sync.Once
	wg    sync.WaitGroup

	procMu sync.Mutex // 同一时刻只处理一个批次，测试里直接调 ProcessOnce 也安全
}

// New 构造流水线（未启动）。队列容量 256，够家用。
func New(st *store.Store, engine ocr.Engine, parser parse.Parser, logger *log.Logger) *Pipeline {
	return &Pipeline{
		st:     st,
		engine: engine,
		parser: parser,
		logger: logger,
		queue:  make(chan int64, 256),
		stop:   make(chan struct{}),
		done:   make(chan struct{}),
	}
}

// Start 启动 worker。
func (p *Pipeline) Start() {
	p.wg.Add(1)
	go func() {
		defer p.wg.Done()
		defer close(p.done)
		for {
			select {
			case <-p.stop:
				return
			case id := <-p.queue:
				if err := p.ProcessOnce(context.Background(), id); err != nil {
					p.logger.Printf("批次 %d 处理失败: %v", id, err)
				}
			}
		}
	}()
}

// Enqueue 把批次放入队列。服务停止后调用会被忽略。
func (p *Pipeline) Enqueue(id int64) {
	select {
	case p.queue <- id:
	case <-p.stop:
	}
}

// Stop 停止接收新任务，并等待正在处理的批次完成。
func (p *Pipeline) Stop() {
	p.once.Do(func() { close(p.stop) })
	p.wg.Wait()
}

// Recover 把上次进程遗留的中间状态改回 pending 并重新入队，返回恢复的批次 id。
func (p *Pipeline) Recover(ctx context.Context) ([]int64, error) {
	ids, err := p.st.ResetInFlight(ctx)
	if err != nil {
		return nil, err
	}
	for _, id := range ids {
		p.Enqueue(id)
	}
	return ids, nil
}

// ProcessOnce 同步处理一个批次，供 worker 与测试使用。
func (p *Pipeline) ProcessOnce(ctx context.Context, id int64) error {
	p.procMu.Lock()
	defer p.procMu.Unlock()

	b, err := p.st.GetBatch(ctx, id)
	if errors.Is(err, store.ErrNotFound) {
		return nil // 排队期间被删了，正常
	}
	if err != nil {
		return err
	}

	if err := p.st.UpdateStatus(ctx, id, store.StatusOCR, ""); err != nil {
		return err
	}

	texts := make([]string, 0, len(b.Images))
	for i := range b.Images {
		img := b.Images[i]
		text := img.OCRRaw
		if strings.TrimSpace(text) == "" {
			cctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
			text, err = p.engine.Recognize(cctx, ocr.Image{
				Path: filepath.Join(p.st.Dir(), img.Path),
				MIME: mimeByExt(img.Path),
			})
			cancel()
			if err != nil {
				return p.fail(ctx, id, fmt.Sprintf("第 %d 张图片识别失败：%v", i+1, err))
			}
			if err := p.st.SetImageOCR(ctx, img.ID, text); err != nil {
				return err
			}
			b.Images[i].OCRRaw = text // 让后面的 image_id 归属判定看得到最新文本
		}
		texts = append(texts, fmt.Sprintf("【第 %d 页】\n%s", i+1, text))
	}

	if err := p.st.UpdateStatus(ctx, id, store.StatusParsing, ""); err != nil {
		return err
	}

	groups, err := p.parser.Parse(ctx, strings.Join(texts, "\n\n"), b.Note)
	if err != nil {
		return p.fail(ctx, id, "分科失败："+err.Error())
	}

	items := toItems(groups, b.Images)
	if len(items) == 0 {
		return p.fail(ctx, id, "没有识别出作业条目")
	}
	if err := p.st.ReplaceItems(ctx, id, items); err != nil {
		return err
	}
	return p.st.UpdateStatus(ctx, id, store.StatusDone, "")
}

func (p *Pipeline) fail(ctx context.Context, id int64, msg string) error {
	if err := p.st.UpdateStatus(ctx, id, store.StatusFailed, msg); err != nil {
		return err
	}
	return errors.New(msg)
}

// toItems 把分科结果展平成 item，并尽量把条目挂到来源图片上：
// 条目文字出现在某张图的 OCR 里就算那张图的，找不到且只有一张图时就挂唯一那张。
func toItems(groups []parse.Group, images []store.Image) []store.NewItem {
	sorted := make([]parse.Group, len(groups))
	copy(sorted, groups)
	sort.SliceStable(sorted, func(i, j int) bool {
		return parse.Order(sorted[i].Subject) < parse.Order(sorted[j].Subject)
	})

	items := []store.NewItem{}
	for _, g := range sorted {
		subject := parse.NormalizeSubject(g.Subject)
		for i, content := range g.Items {
			items = append(items, store.NewItem{
				ImageID: matchImage(content, images),
				Subject: subject,
				Content: content,
				Sort:    i,
			})
		}
	}
	return items
}

func matchImage(content string, images []store.Image) int64 {
	needle := normalizeSpace(content)
	if needle != "" {
		for _, img := range images {
			if strings.Contains(normalizeSpace(img.OCRRaw), needle) {
				return img.ID
			}
		}
	}
	if len(images) == 1 {
		return images[0].ID
	}
	return 0
}

func normalizeSpace(s string) string {
	return strings.Join(strings.Fields(s), "")
}

func mimeByExt(path string) string {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".png":
		return "image/png"
	case ".webp":
		return "image/webp"
	case ".heic":
		return "image/heic"
	default:
		return "image/jpeg"
	}
}
