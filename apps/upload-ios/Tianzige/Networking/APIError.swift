import Foundation

enum APIError: Error {
    /// 30s 内没传完 / 8s 内没连上
    case timeout
    case network(String)
    /// 服务端返回了统一错误体。code 用于查本地文案，message 只是兜底。
    case server(code: String, message: String)
    case unexpectedStatus(Int)
    case decoding

    /// 给用户看的一句话。
    /// 优先按 `code` 用本地文案（服务端 message 是中文，英文环境下不能直接展示），
    /// 码不认识时才退回服务端那句 message。
    var userMessage: String {
        switch self {
        case .timeout, .network:
            return L10n.string("error.timeout")
        case let .server(code, message):
            if let key = Self.localizationKey(for: code) {
                return L10n.string(key)
            }
            return message
        case .unexpectedStatus:
            return L10n.string("error.uploadFailed")
        case .decoding:
            return L10n.string("error.badResponse")
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

    /// 是不是「连不上」这一类。是的话顶部挂黄条，提示检查地址或网络。
    var isConnectionProblem: Bool {
        switch self {
        case .timeout, .network:
            return true
        case .server, .unexpectedStatus, .decoding:
            return false
        }
    }
}
