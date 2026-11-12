# ProtocolTests · iOS 端接口对照

> 人肉对照 `spec/openapi.yaml` 用。列出 iOS 端实际发出的每个请求和期望的响应，
> 以及 Swift 模型与 schema 字段的一一对应关系。
> 实现在 `Tianzige/Networking/APIClient.swift`。

## 1. GET /api/health

对应 operationId：`getHealth`。

### 请求

```
GET {base}/api/health HTTP/1.1
Host: nas.local:8080
Accept: application/json
```

- `{base}` 来自设置页，默认 `http://nas.local:8080`
- 客户端超时 8s（连通性测试不能让人干等 30s）

curl 等价：

```bash
curl -i http://nas.local:8080/api/health
```

### 期望响应（spec: 200）

```json
{
  "ok": true,
  "version": "1.0.0",
  "time": "2026-11-12T20:30:00+08:00",
  "db": "ok",
  "ocr": "ok"
}
```

### Swift 模型 `HealthResponse`

| JSON 字段 | Swift 属性 | 类型 | 必填 | 说明 |
|---|---|---|---|---|
| `ok` | `ok` | `Bool` | ✅ | false 也按「连不上」处理 |
| `version` | `version` | `String` | ✅ | 设置页显示「已连接 · 服务端版本 x」 |
| `time` | `time` | `String` | ✅ | 保留原文不解析 |
| `db` | `db` | `String?` | — | 仅排障 |
| `ocr` | `ocr` | `String?` | — | 仅排障 |

### 客户端行为

| 情况 | 行为 |
|---|---|
| 200 + `ok: true` | 黄条消失；设置页显示绿色「已连接 · 服务端版本 x」 |
| 200 + `ok: false` | 按连不上处理（黄条 / 设置页红字） |
| 超时 / 连接拒绝 / 非 2xx | 黄条「连不上 NAS，检查地址或网络」 |

## 2. POST /api/ingest

对应 operationId：`ingest`。**这是上传端唯一的主接口。**

### 请求

```
POST {base}/api/ingest HTTP/1.1
Host: nas.local:8080
Accept: application/json
Content-Type: multipart/form-data; boundary=Tianzige-<UUID>
```

multipart 各 part（字段名与 `apps/upload-web/upload.html` 一致）：

```
--Tianzige-<UUID>
Content-Disposition: form-data; name="files[]"; filename="photo-a1b2c3d4.jpg"
Content-Type: image/jpeg

<JPEG 二进制，最长边 2048px、质量 0.85>
--Tianzige-<UUID>
Content-Disposition: form-data; name="files[]"; filename="photo-e5f6a7b8.jpg"
Content-Type: image/jpeg

<JPEG 二进制>
--Tianzige-<UUID>
Content-Disposition: form-data; name="note"

数学练习册 P18
--Tianzige-<UUID>
Content-Disposition: form-data; name="date"

2026-11-12
--Tianzige-<UUID>--
```

- `files[]` 可重复 1–6 次（spec: `minItems: 1, maxItems: 6`）
- `note` 只在非空时附加（spec: 可空，maxLength 500，客户端截断）
- `date` 恒定发送，`YYYY-MM-DD`，按 **Asia/Shanghai** 格式化
  （spec: `pattern: ^\d{4}-\d{2}-\d{2}$`；协议 §6：不用 UTC 推日期）
- 客户端超时 30s（upload-ui.md §3 铁律 3）

curl 等价：

```bash
curl -i http://nas.local:8080/api/ingest \
  -F 'files[]=@photo1.jpg;type=image/jpeg' \
  -F 'files[]=@photo2.jpg;type=image/jpeg' \
  -F 'note=数学练习册 P18' \
  -F 'date=2026-11-12'
```

### 期望响应（spec: 202）

```json
{
  "batch_id": 318,
  "status": "pending",
  "date": "2026-11-12",
  "image_count": 3,
  "duplicate_of": null
}
```

重复上传时的响应（软去重，不报错、**不新建记录**，`batch_id` 即已有批次）：

```json
{
  "batch_id": 217,
  "status": "done",
  "date": "2026-11-11",
  "image_count": 3,
  "duplicate_of": 217
}
```

### Swift 模型 `IngestResponse`

| JSON 字段 | Swift 属性 | 类型 | 必填 | 说明 |
|---|---|---|---|---|
| `batch_id` | `batchID` | `Int` | ✅ | 客户端只记录不展示 |
| `status` | `status` | `BatchStatus` | ✅ | 枚举见下 |
| `date` | `date` | `String` | ✅ | `YYYY-MM-DD` |
| `image_count` | `imageCount` | `Int` | ✅ | toast「收到 N 张」用 |
| `duplicate_of` | `duplicateOf` | `Int?` | — | 有值 → 「这些图片之前传过了，没有重复入库」 |

`BatchStatus`（spec: `pending | ocr | parsing | done | failed`）：
解码时未知值回落为 `.pending`，协议加状态不至于整体解码失败。

### 客户端行为（upload-ui.md §3）

| 情况 | 行为 |
|---|---|
| **202** | 立即清空表单（图片、备注、日期归位）+ toast「收到 N 张，处理完电视上就有」，6s 消失。**不轮询、不等识别** |
| 202 且 `duplicate_of` 有值 | 同样清空表单，toast 改为「这些图片之前传过了，没有重复入库」 |
| 400 / 413 / 415（有统一错误体） | 按钮变红「没传上去，点这里重试」，已选图片保留；toast 展示服务端 `message` |
| 超时 / 网络错误 | 按钮变红 + 图片保留 + 顶部黄条「连不上 NAS，检查地址或网络」 |
| 非 2xx 且无错误体 | 按钮变红，toast「这次没传上去，点一下再试」 |

### 错误响应对照（spec: components/responses）

| HTTP | 场景 | 响应体 | 客户端展示 |
|---|---|---|---|
| 400 | 超过 6 张 | `{"error":{"code":"too_many_files","message":"…"}}` | 服务端 message（客户端已前置限制为 6 张，正常到不了这里） |
| 413 | 单张 > 20MB | `{"error":{"code":"file_too_large","message":"单张图片不能超过 20MB"}}` | 服务端 message |
| 415 | 类型不支持 | `{"error":{"code":"unsupported_type","message":"只接受 jpg/png/heic/webp"}}` | 服务端 message |

> iOS 端在上传前已把所有图压成 JPEG ≤2048px，413/415 理论上到不了；
> 仍然按统一错误体解析，防服务端策略变化。

## 3. 明确不调的接口

| 接口 | 为什么不调 |
|---|---|
| `GET /api/batches` | 最近上传列表是 Web 端的事（upload-ui.md §4） |
| `POST /api/batch/{id}/rerun` | 重跑是 Web 端的事 |
| `DELETE /api/batch/{id}` | 删除是 Web 端的事 |
| `GET /api/day`、`GET /api/days` | 电视端专用 |
| `GET /img/{date}/{filename}` | iOS 不看图 |

## 4. 客户端必须容忍的点（docs/05-协议.md §9）

- 响应里出现未知字段：`Decodable` 默认忽略 ✅
- `status` 出现未知枚举值：回落 `.pending` ✅
- `date` / `time` 只当字符串，不做时区换算 ✅
- 所有 URL 由客户端拼 base（本端不消费图片 URL）✅
