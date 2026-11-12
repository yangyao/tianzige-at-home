import Foundation

/// 本地设置。只有一个可改项：NAS 地址，存 UserDefaults。
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    static let defaultBaseURLString = "http://nas.local:8080"
    private static let storageKey = "nas.baseURL"

    @Published var baseURLString: String {
        didSet {
            UserDefaults.standard.set(baseURLString, forKey: Self.storageKey)
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
        baseURLString = saved.isEmpty ? Self.defaultBaseURLString : saved
    }

    /// 请求用的 base URL。缺协议头自动补 http://，末尾斜杠去掉。
    var baseURL: URL {
        URL(string: Self.normalize(baseURLString))
            ?? URL(string: Self.defaultBaseURLString)!
    }

    /// 给设置页做即时校验：必须能解析出 host。
    static func isValid(_ raw: String) -> Bool {
        guard let url = URL(string: normalize(raw)),
              let host = url.host,
              !host.isEmpty else { return false }
        return true
    }

    static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return defaultBaseURLString }
        let lowercased = value.lowercased()
        if !lowercased.hasPrefix("http://") && !lowercased.hasPrefix("https://") {
            value = "http://" + value
        }
        // 只去掉主机之后的尾斜杠，别把 "http://" 削成 "http:"
        let schemeLength = value.lowercased().hasPrefix("https://") ? 8 : 7
        while value.count > schemeLength && value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
