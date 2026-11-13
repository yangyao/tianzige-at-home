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

/// 客户端能区分的几种失败。message 一律是给人看的一句话，不出现技术词。
enum IngestError: Error, Equatable {
    /// 设置里的地址根本拼不出 URL
    case badAddress
    /// 30 秒没回来
    case timeout
    /// 连不上 / 断网 / 地址写错
    case offline
    /// 服务端明确拒绝（4xx / 5xx）。code 用来查本地文案，message 只是兜底。
    case server(status: Int, code: String?, message: String?)
    /// 回话看不懂
    case malformed

    var userMessage: String {
        switch self {
        case .badAddress:
            return L10n.string("error.badAddress")
        case .timeout:
            return L10n.string("error.timeout")
        case .offline:
            return L10n.string("error.offline")
        case .server(_, let code, let message):
            if let code, let key = Self.localizationKey(for: code) {
                return L10n.string(key)
            }
            if let message, !message.isEmpty { return message }
            return L10n.string("error.uploadFailed")
        case .malformed:
            return L10n.string("error.uploadFailed")
        }
    }

    /// 错误码 → 文案 key，对照 docs/12-国际化.md §6。
    private static func localizationKey(for code: String) -> String? {
        switch code {
        case "bad_request": return "error.badRequest"
        case "invalid_date": return "error.invalidDate"
        case "too_many_files": return "error.tooManyFiles"
        case "file_too_large": return "error.fileTooLarge"
        case "unsupported_type": return "error.unsupportedType"
        case "not_found": return "error.notFound"
        case "ocr_failed": return "error.ocrFailed"
        case "parse_failed": return "error.parseFailed"
        case "llm_unavailable": return "error.llmUnavailable"
        case "internal": return "error.internal"
        default: return nil
        }
    }
}
