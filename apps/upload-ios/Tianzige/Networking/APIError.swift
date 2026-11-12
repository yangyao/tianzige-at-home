import Foundation

enum APIError: Error {
    /// 30s 内没传完 / 8s 内没连上
    case timeout
    case network(String)
    /// 服务端返回了统一错误体，message 是可直接展示的中文
    case server(code: String, message: String)
    case unexpectedStatus(Int)
    case decoding

    /// 给用户看的一句话。服务端的 message 本身就是中文说明，原样展示。
    var userMessage: String {
        switch self {
        case .timeout, .network:
            return "没传上去，检查一下 Wi-Fi 再试"
        case let .server(_, message):
            return message
        case .unexpectedStatus:
            return "这次没传上去，点一下再试"
        case .decoding:
            return "NAS 回的内容看不懂，检查地址对不对"
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
