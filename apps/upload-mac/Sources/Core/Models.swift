import Foundation

/// UserDefaults / @AppStorage 的键，只在这里定义，避免两边写错字符串。
enum DefaultsKey {
    static let nasBaseURL = "nasBaseURL"
    static let lastUploadCount = "lastUploadCount"
    static let lastUploadAt = "lastUploadAt"
    static let lastUploadDuplicate = "lastUploadDuplicate"
}

/// POST /api/ingest 的 202 响应体，字段定义见 spec/openapi.yaml → IngestResponse
struct IngestResponse: Decodable, Equatable {
    let batchId: Int
    let status: String
    let date: String
    let imageCount: Int
    /// 全部图片与某个已有批次完全相同时才有值，此时服务端不新建记录。
    let duplicateOf: Int?

    enum CodingKeys: String, CodingKey {
        case batchId = "batch_id"
        case status
        case date
        case imageCount = "image_count"
        case duplicateOf = "duplicate_of"
    }
}

/// GET /api/health 的 200 响应体。除 ok 外都可能缺，解码时按可选处理。
struct HealthResponse: Decodable {
    let ok: Bool
    let version: String?
    let time: String?
    let db: String?
    let ocr: String?
}

/// 服务端的统一错误体：{ "error": { "code", "message" } }
struct APIErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let code: String
        let message: String
    }

    let error: Payload
}

/// 客户端能区分的几种失败。message 一律是给人看的中文，不出现技术词。
enum IngestError: Error, Equatable {
    /// 设置里的地址根本拼不出 URL
    case badAddress
    /// 30 秒没回来
    case timeout
    /// 连不上 / 断网 / 地址写错
    case offline
    /// 服务端明确拒绝（4xx / 5xx），message 是服务端那句中文
    case server(status: Int, message: String?)
    /// 回话看不懂
    case malformed

    var userMessage: String {
        switch self {
        case .badAddress:
            return "地址填得不对，去设置里改一下"
        case .timeout:
            return "等太久了，没传上去，点这里重试"
        case .offline:
            return "连不上 NAS，检查地址或网络"
        case .server(_, let message):
            if let message, !message.isEmpty { return message }
            return "这次没传上去，点这里重试"
        case .malformed:
            return "这次没传上去，点这里重试"
        }
    }
}
