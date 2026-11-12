# homework-server · NAS 服务

Go + SQLite，单二进制，只监听局域网。

## 状态

**未开始。** 接口已定，见 `docs/03-接口.md`。

## 结构（计划）

```
main.go
internal/
  store/       SQLite 读写
  handler/     HTTP 路由
  ocr/         OCR 适配层（云 API / 本地）
  parse/       LLM 分科，JSON Schema 约束
  source/      采集来源接口（qq-mac / web / folder）
web/           upload.html、today.html（go:embed）
```

## 要点

- `modernc.org/sqlite`，避免 CGO，方便交叉编译到 ARM NAS
- `/ingest` 落盘后立刻返回，识别走 goroutine 队列（并发 1，够用）
- 识别失败只把 `status` 改成 `failed`，图片不动，可随时 rerun
- 静态文件用 `go:embed`，部署只有一个二进制

## 运行

```bash
go run . -addr :8080 -data /volume1/homework
```
