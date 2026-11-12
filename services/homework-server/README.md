> 2026-11-12 实测更新：已用本机 Go 1.20.5 构建并部署到真实 Linux arm64 NAS。
> 默认使用私有文件中的 Z.AI 配置与 glm-5.3-flash；缺少密钥时只保留原图，不返回示例作业。
> 构建入口 make test bundle，产物在仓库 dist/。配置见 ../../docs/07-AI配置.md。

# homework-server · NAS 服务

Go + SQLite，单二进制，只监听局域网。协议以 [`spec/openapi.yaml`](../../spec/openapi.yaml) 为唯一真源。

## 状态

**可用。** 9 个接口全部实现，识别流水线、软去重、rerun、静态图片、优雅退出均已打通。

## 结构

```
cmd/server/main.go     启动参数、引擎装配、优雅退出
internal/
  store/     SQLite（WAL + foreign_keys），建表与读写
  pipeline/  识别流水线：pending→ocr→parsing→done/failed，单 worker 串行队列
  ocr/       Engine 接口 + MockEngine / OpenAICompatEngine
  parse/     Parser 接口 + LLMParser / LineParser
  api/       路由、multipart 接入、聚合、错误码、CORS、/img 静态
scripts/demo.sh         端到端 curl 演示
```

## 运行

```bash
go build ./cmd/server
./server -addr :8080 -data /volume1/homework [-web ./web]
```

| 参数/环境变量 | 说明 |
|---|---|
| `-addr` | 监听地址，默认 `:8080` |
| `-data` | 数据目录（`hw.db` + `YYYY-MM-DD/` 图片），默认 `./data` |
| `-web` | 可选，静态站点目录挂到 `/`（上传网页）；不指定则不挂 |
| `TIANZIGE_OCR=mock\|openai` | OCR 引擎，默认 mock（未配置 key 时） |
| `TIANZIGE_LLM=lines\|openai` | 分科器，默认 lines（未配置 key 时） |
| `OPENAI_BASE_URL` | 兼容接口的 base，如 `https://api.openai.com/v1` |
| `OPENAI_API_KEY` | 密钥；为空时自动退回 mock/lines |
| `OPENAI_MODEL` | 模型名，默认 `gpt-4o-mini` |

离线跑通全部链路（mock OCR + 行分科）：

```bash
sh scripts/demo.sh
```

它会编译、起服务、上传一张图、轮询到 `done`、读 `/api/day`、取回原图并逐字节比对。

## 数据库

按 `docs/03-接口.md` 建表。`item` 是派生数据，`checkin` 是用户数据：
rerun 只清空 `item`，打勾状态按 `sha256(subject+content)` 独立保存，重跑不丢。

## 已知限制

- 软去重只认「整批图片完全相同」；部分重复会生成新批次。
- 单 worker 串行识别，一次只处理一个批次（家用够了）。
- HEIC 不取宽高（填 0，客户端自行占位）；OCR 需要模型侧支持该格式。
- 未做鉴权，仅限局域网。
