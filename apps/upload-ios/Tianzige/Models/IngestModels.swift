import Foundation

/// `POST /api/ingest` 的响应。
/// 字段与 `spec/openapi.yaml#/components/schemas/IngestResponse` 一一对应。
struct IngestResponse: Decodable, Equatable {
    /// 服务端批次 id，用于后续查询与重跑。上传端只记录不展示。
    let batchID: Int
    let status: BatchStatus
    /// 归属日期，YYYY-MM-DD。
    let date: String
    /// 这次实际落盘的图片数，用于 toast 文案「收到 N 张」。
    let imageCount: Int
    /// 所有图片与某个已有批次完全相同（sha256）时，返回那个批次 id，且不新建记录。
    /// 有值就提示「这些图片之前传过了」，不报错。
    let duplicateOf: Int?

    enum CodingKeys: String, CodingKey {
        case batchID = "batch_id"
        case status
        case date
        case imageCount = "image_count"
        case duplicateOf = "duplicate_of"
    }
}

/// 批次状态机：pending → ocr → parsing → done，任一环节失败落 failed。
/// 上传端不按状态值写死 UI；未知值按 pending 处理，协议加状态时不至于解码失败。
enum BatchStatus: String, Decodable {
    case pending
    case ocr
    case parsing
    case done
    case failed

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BatchStatus(rawValue: raw) ?? .pending
    }
}

/// `GET /api/health` 的响应，只用于「测试连接」和顶部提示条。
struct HealthResponse: Decodable, Equatable {
    let ok: Bool
    let version: String
    /// RFC3339 带 +08:00 偏移。保留原文，不参与任何计算。
    let time: String
    /// ok / error
    let db: String?
    /// ok / unavailable / unconfigured，仅排障用
    let ocr: String?
}

/// 统一错误体：`{ "error": { "code": "...", "message": "..." } }`
/// message 是服务端给好的中文句子，客户端直接展示，不自己拼。
struct APIErrorResponse: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
    }

    let error: Body
}
