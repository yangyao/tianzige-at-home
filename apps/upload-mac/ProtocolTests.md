# 接口联调对照 · upload-mac

本端只调两个接口，字段以 [`spec/openapi.yaml`](../../spec/openapi.yaml) 为准。
本文给的是**客户端实际发出的请求**和**期望收到的响应**，方便在 NAS 上起服务后用 curl 对照。

```bash
BASE=http://nas.local:8080     # 换成你 NAS 的地址
```

## 1. 健康检查

### 请求

```bash
curl -sS -i "$BASE/api/health"
```

```http
GET /api/health HTTP/1.1
Accept: application/json
```

### 200 响应

```json
{
  "ok": true,
  "version": "1.0.0",
  "time": "2026-11-12T20:30:00+08:00",
  "db": "ok",
  "ocr": "ok"
}
```

### 客户端怎么用

- 打开上传窗口 / 设置窗口时各查一次，超时 6s。
- 只有 **明确失败或 `ok=false`** 才在窗口顶部显示黄条「连不上 NAS，检查地址或网络」。
- 设置窗口的「测试连接」就是这一条请求，成功显示「连上了，NAS 正常」。
- 健康检查失败不影响上传按钮可用性（可能是 health 挂了但 ingest 正常），失败后仍可点上传。

## 2. 上传一批图片

### 请求

```bash
curl -sS -i -X POST "$BASE/api/ingest" \
  -F "files=@/tmp/photo-1.jpg;type=image/jpeg" \
  -F "files=@/tmp/photo-2.jpg;type=image/jpeg" \
  -F "files=@/tmp/photo-3.jpg;type=image/jpeg" \
  -F "note=今天作业在黑板上了，数学要带尺子" \
  -F "date=2026-11-12"
```

客户端发出的 multipart 原文（boundary 每次随机）：

```http
POST /api/ingest HTTP/1.1
Content-Type: multipart/form-data; boundary=tianzige-6F0F2A0E-...
Accept: application/json
```

```text
--tianzige-6F0F2A0E-...
Content-Disposition: form-data; name="files"; filename="photo-1.jpg"
Content-Type: image/jpeg

<JPEG 二进制>
--tianzige-6F0F2A0E-...
Content-Disposition: form-data; name="files"; filename="photo-2.jpg"
Content-Type: image/jpeg

<JPEG 二进制>
--tianzige-6F0F2A0E-...
Content-Disposition: form-data; name="date"

2026-11-12
--tianzige-6F0F2A0E-...
Content-Disposition: form-data; name="note"

今天作业在黑板上了，数学要带尺子
--tianzige-6F0F2A0E-...--
```

要点：

- 字段名是 **`files`**（可重复），与 openapi 的 `files` 数组一致；`name` 和 `note` 一样是普通文本字段。
- 图片在客户端已经统一转成 JPEG（最长边 2048、质量 0.85），所以永远 `image/jpeg`、`photo-N.jpg`。
- `note` 为空时**整个字段不发送**；`date` 一定发送，格式 `YYYY-MM-DD`（Asia/Shanghai 的那一天）。
- 单批 1–6 张（客户端就已经截断到 6 张），单张压缩后远小于 20MB。

### 202 响应（正常入库）

```json
{
  "batch_id": 318,
  "status": "pending",
  "date": "2026-11-12",
  "image_count": 3
}
```

客户端行为：**立即清空图片和备注、日期回到今天**，toast「收到 3 张，处理完电视上就有」，写入菜单栏「上次：✓ 3 张 · 17:32」。
不轮询、不查批次详情，用户此时可以关窗口。

### 202 响应（全部重复）

```json
{
  "batch_id": 305,
  "status": "done",
  "date": "2026-11-12",
  "image_count": 3,
  "duplicate_of": 305
}
```

客户端行为：同样清空表单，toast 改成「这些图片之前传过了，没有重复入库」，菜单栏记录成「上次：之前传过 · 17:32」。
`duplicate_of` 有值时 `batch_id` 是那个已有批次，不新建记录——这是软去重，不是错误。

## 3. 错误响应与客户端处理

统一错误体：

```json
{ "error": { "code": "file_too_large", "message": "单张图片不能超过 20MB" } }
```

| 场景 | HTTP | 响应示例 | 客户端表现 |
|---|---|---|---|
| 超过 6 张 | 400 | `{"error":{"code":"too_many_files","message":"一次最多 6 张"}}` | 按钮变红「没传上去，点这里重试」，红字显示服务端 message，图片保留 |
| 日期格式错 | 400 | `{"error":{"code":"invalid_date","message":"日期格式应为 YYYY-MM-DD"}}` | 同上 |
| 图片过大 | 413 | `{"error":{"code":"file_too_large","message":"单张图片不能超过 20MB"}}` | 同上 |
| 类型不支持 | 415 | `{"error":{"code":"unsupported_type","message":"只接受 jpg/png/heic/webp"}}` | 同上 |
| 服务端内部错误 | 500 | `{"error":{"code":"internal","message":"服务内部错误"}}` | 同上（不重试循环，等用户点） |
| 30 秒没响应 | — | 无 | 「等太久了，没传上去，点这里重试」，图片保留 |
| 连不上 / DNS 错 | — | 无 | 「没传上去，点这里重试」+ 顶部黄条，图片保留 |
| 202 但回话解析失败 | 202 | 非 JSON | 当作失败处理（不会误以为已入库） |

文案原则：服务端 `message` 是可直接展示的中文，客户端优先用它；网络层错误用固定中文，不暴露状态码、不出现「批次」「OCR」这类词。

## 4. 手工联调顺序

1. NAS 上起服务，确认 `curl -sS "$BASE/api/health"` 返回 `"ok": true`。
2. `curl` 上传 3 张图（上面的命令），确认 202 + `image_count`。
3. 再执行一次同样的命令，确认返回 `duplicate_of`。
4. 打开 App → 设置里填同一个地址 → 测试连接显示「连上了，NAS 正常」。
5. 截图后切到上传窗口按 ⌘V，缩略图出现 → 上传 → toast「收到 N 张…」。
6. 把 NAS 服务停掉，再传一次：按钮变红、黄条出现、图片还在；恢复服务后点红色按钮，能传上去。
7. 拖 7 张图进窗口：只进 6 张，红字提示「一次最多传 6 张，多出来的 1 张没放进来」。
8. 从 Finder 把图片拖到 Dock 里的 App 图标：窗口弹出且图片在列表里（App 窗口开着时 Dock 才有图标）。
