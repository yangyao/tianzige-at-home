import Foundation

/// 磁盘缓存（UserDefaults 承载，量级就一天的数据 + 一周的圆点，够了）。
/// 按「服务端地址 | 类型」做 key，换 NAS 之后永远不会显示上一台 NAS 的数据。
struct CacheStore {
    private let settings: SettingsStore
    private let defaults: UserDefaults

    init(settings: SettingsStore = SettingsStore(), defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
    }

    private func key(_ kind: String) -> String {
        settings.serverUrl() + "|" + kind
    }

    func readDay() -> CachedDay? {
        guard let data = defaults.data(forKey: key("day")) else { return nil }
        return try? JSONDecoder().decode(CachedDay.self, from: data)
    }

    func readMarks() -> [DayMark]? {
        guard let data = defaults.data(forKey: key("marks")) else { return nil }
        return (try? JSONDecoder().decode([DayMark].self, from: data))
    }

    func writeDay(_ day: DayView) {
        let value = CachedDay(day: day, savedAt: Date().timeIntervalSince1970)
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key("day"))
        }
    }

    func writeMarks(_ marks: [DayMark]) {
        if let data = try? JSONEncoder().encode(marks) {
            defaults.set(data, forKey: key("marks"))
        }
    }
}
