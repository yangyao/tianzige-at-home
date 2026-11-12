package pipeline

import (
	"context"
	"io"
	"log"
	"testing"
	"time"

	"github.com/yangyao/tianzige-at-home/homework-server/internal/ocr"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/parse"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/store"
)

type waitingEngine struct{ entered chan struct{} }

func (e *waitingEngine) Name() string   { return "waiting" }
func (e *waitingEngine) Status() string { return "ok" }
func (e *waitingEngine) Recognize(ctx context.Context, _ ocr.Image) (string, error) {
	close(e.entered)
	<-ctx.Done()
	return "", ctx.Err()
}

func TestStopCancelsRecognitionAndKeepsBatchRecoverable(t *testing.T) {
	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	id, err := st.CreateBatch(context.Background(), store.Today(), "", []store.ImageMeta{{Ext: ".png", SHA256: "test"}})
	if err != nil {
		t.Fatal(err)
	}
	engine := &waitingEngine{entered: make(chan struct{})}
	p := New(st, engine, parse.NewLineParser(), log.New(io.Discard, "", 0))
	p.Start()
	p.Enqueue(id)
	select {
	case <-engine.entered:
	case <-time.After(2 * time.Second):
		t.Fatal("worker did not begin")
	}
	done := make(chan struct{})
	go func() { p.Stop(); close(done) }()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("shutdown waited for OCR timeout")
	}
	ids, err := st.ResetInFlight(context.Background())
	if err != nil || len(ids) != 1 || ids[0] != id {
		t.Fatalf("batch not recoverable after shutdown: %v, %v", ids, err)
	}
}
