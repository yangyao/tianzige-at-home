package pipeline

import (
	"context"
	"io"
	"log"
	"sync/atomic"
	"testing"
	"time"

	"github.com/yangyao/tianzige-at-home/homework-server/internal/ocr"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/parse"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/store"
)

type heldEngine struct{ entered, release chan struct{} }

func (*heldEngine) Name() string   { return "held" }
func (*heldEngine) Status() string { return "ok" }
func (e *heldEngine) Recognize(ctx context.Context, _ ocr.Image) (string, error) {
	close(e.entered)
	select {
	case <-e.release:
		return "原始作业", nil
	case <-ctx.Done():
		return "", ctx.Err()
	}
}

type namedParser string

func (p namedParser) Name() string { return string(p) }
func (p namedParser) Parse(context.Context, string, string) ([]parse.Group, error) {
	return []parse.Group{{Subject: "语文", Items: []string{string(p)}}}, nil
}

type modelPair struct {
	engine ocr.Engine
	parser parse.Parser
}

func TestProviderSwitchKeepsInFlightBatchConsistent(t *testing.T) {
	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	engine := &heldEngine{entered: make(chan struct{}), release: make(chan struct{})}
	var active atomic.Value
	active.Store(modelPair{engine, namedParser("旧模型")})
	p := New(st, engine, namedParser("旧模型"), log.New(io.Discard, "", 0))
	defer p.Stop()
	p.SetProvider(func() (ocr.Engine, parse.Parser) { pair := active.Load().(modelPair); return pair.engine, pair.parser })
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	id, err := st.CreateBatch(ctx, store.Today(), "", []store.ImageMeta{{Ext: ".png", SHA256: "first"}})
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() { done <- p.ProcessOnce(ctx, id) }()
	select {
	case <-engine.entered:
	case <-ctx.Done():
		t.Fatal("worker never started")
	}
	active.Store(modelPair{ocr.NewMock(), namedParser("新模型")})
	close(engine.release)
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	b, err := st.GetBatch(ctx, id)
	if err != nil || len(b.Items) != 1 || b.Items[0].Content != "旧模型" {
		t.Fatal("in-flight batch mixed old OCR and new parser")
	}
	id, err = st.CreateBatch(ctx, store.Today(), "", []store.ImageMeta{{Ext: ".png", SHA256: "second"}})
	if err != nil {
		t.Fatal(err)
	}
	if err := p.ProcessOnce(ctx, id); err != nil {
		t.Fatal(err)
	}
	b, err = st.GetBatch(ctx, id)
	if err != nil || len(b.Items) != 1 || b.Items[0].Content != "新模型" {
		t.Fatal("next batch did not use new model")
	}
}
