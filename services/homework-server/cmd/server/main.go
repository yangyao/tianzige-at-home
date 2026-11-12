package main

import (
	"context"
	"errors"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/yangyao/tianzige-at-home/homework-server/internal/api"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/ocr"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/parse"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/pipeline"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/store"
)

const version = "1.0.0"

func main() {
	addr := flag.String("addr", ":8080", "监听地址")
	dataDir := flag.String("data", "./data", "数据目录（SQLite 与图片）")
	webDir := flag.String("web", "", "可选的静态站点目录，挂到 / 根路径")
	flag.Parse()

	logger := log.New(os.Stdout, "[homework] ", log.LstdFlags|log.Lmsgprefix)

	if *webDir != "" {
		if info, err := os.Stat(*webDir); err != nil || !info.IsDir() {
			logger.Fatalf("-web 目录不可用: %s", *webDir)
		}
	}

	st, err := store.Open(*dataDir)
	if err != nil {
		logger.Fatalf("初始化存储失败: %v", err)
	}
	defer st.Close()

	engine := buildOCREngine(logger)
	parser := buildParser(logger)
	logger.Printf("OCR 引擎: %s (%s)，分科器: %s", engine.Name(), engine.Status(), parser.Name())

	pl := pipeline.New(st, engine, parser, logger)
	pl.Start()

	ctx := context.Background()
	if ids, err := pl.Recover(ctx); err != nil {
		logger.Printf("恢复未完成批次失败: %v", err)
	} else if len(ids) > 0 {
		logger.Printf("恢复 %d 个未完成批次: %v", len(ids), ids)
	}

	srv := api.New(st, pl, api.Options{DataDir: *dataDir, WebDir: *webDir, Version: version}, logger)
	srv.SetOCRStatus(engine.Status)

	httpSrv := &http.Server{
		Addr:              *addr,
		Handler:           srv,
		ReadHeaderTimeout: 15 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	go func() {
		logger.Printf("监听 %s，数据目录 %s", *addr, *dataDir)
		if err := httpSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Fatalf("HTTP 服务异常退出: %v", err)
		}
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	sig := <-sigCh
	logger.Printf("收到信号 %s，开始优雅退出", sig)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpSrv.Shutdown(shutdownCtx); err != nil {
		logger.Printf("HTTP 关闭异常: %v", err)
	}
	// 等正在处理的那个批次写完再退出，队列里没跑的留在 pending，下次启动会恢复。
	pl.Stop()
	logger.Printf("已退出")
}

func buildOCREngine(logger *log.Logger) ocr.Engine {
	choice := strings.ToLower(strings.TrimSpace(os.Getenv("TIANZIGE_OCR")))
	base, key, model := openAIConfig()
	switch choice {
	case "openai":
		return ocr.NewOpenAICompat(base, key, model)
	case "mock":
		return ocr.NewMock()
	case "":
		if base != "" && key != "" && model != "" {
			return ocr.NewOpenAICompat(base, key, model)
		}
		return ocr.NewMock()
	default:
		logger.Printf("未知的 TIANZIGE_OCR=%q，回退到 mock", choice)
		return ocr.NewMock()
	}
}

func buildParser(logger *log.Logger) parse.Parser {
	choice := strings.ToLower(strings.TrimSpace(os.Getenv("TIANZIGE_LLM")))
	base, key, model := openAIConfig()
	switch choice {
	case "openai":
		return parse.NewLLMParser(base, key, model)
	case "lines":
		return parse.NewLineParser()
	case "":
		if base != "" && key != "" && model != "" {
			return parse.NewLLMParser(base, key, model)
		}
		return parse.NewLineParser()
	default:
		logger.Printf("未知的 TIANZIGE_LLM=%q，回退到 lines", choice)
		return parse.NewLineParser()
	}
}

func openAIConfig() (base, key, model string) {
	base = strings.TrimSpace(os.Getenv("OPENAI_BASE_URL"))
	key = strings.TrimSpace(os.Getenv("OPENAI_API_KEY"))
	model = strings.TrimSpace(os.Getenv("OPENAI_MODEL"))
	if base == "" {
		base = "https://api.openai.com/v1"
	}
	if model == "" {
		model = "gpt-4o-mini"
	}
	return base, key, model
}
