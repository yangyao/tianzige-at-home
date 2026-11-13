import Foundation

/// 服务端地址存 UserDefaults。改 NAS 后旧缓存靠「key 带地址」自动隔离（见 CacheStore）。
struct SettingsStore {
    private let defaults: UserDefaults
    private let key = "server-url"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func serverUrl() -> String {
        defaults.string(forKey: key) ?? DEFAULT_SERVER_URL
    }

    func saveServerUrl(_ url: String) {
        defaults.set(DayLogic.normalizeServerUrl(url), forKey: key)
    }
}
