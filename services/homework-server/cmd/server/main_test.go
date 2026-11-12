package main

import (
	"context"
	"io"
	"log"
	"testing"

	"github.com/yangyao/tianzige-at-home/homework-server/internal/ocr"
)

func TestUnconfiguredOCRNeverInventsHomework(t *testing.T) {
	for _, choice := range []string{"", "typo"} {
		t.Run(choice, func(t *testing.T) {
			t.Setenv("TIANZIGE_OCR", choice)
			t.Setenv("OPENAI_API_KEY", "")
			e := buildOCREngine(log.New(io.Discard, "", 0))
			text, err := e.Recognize(context.Background(), ocr.Image{})
			if e.Status() != "unconfigured" || text != "" || err == nil {
				t.Fatalf("unconfigured engine produced homework: status=%s text=%q err=%v", e.Status(), text, err)
			}
		})
	}
}

func TestMockRequiresExplicitChoice(t *testing.T) {
	t.Setenv("TIANZIGE_OCR", "mock")
	e := buildOCREngine(log.New(io.Discard, "", 0))
	if e.Name() != "mock" {
		t.Fatal(e.Name())
	}
}
