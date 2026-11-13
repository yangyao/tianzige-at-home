import Foundation

/// 服务端默认地址（docs/05-协议.md §8）。
let DEFAULT_SERVER_URL = "http://nas.local:8080"

/// 日期条允许回看 / 前看的天数。
let MAX_DAYS_BACK = 56
let MAX_DAYS_FORWARD = 6

/// 异常 → 一个语义化的错误种类。文案在 UI 层按当前语言查 Localizable.strings，
/// domain 里不出现面向用户的字符串。原则见 DESIGN.md §9：主文案说结论，副文案给出路。
enum ErrorKind {
    case timeout
    case hostNotFound
    case connectFailed
    case badData
    case badAddress
    case network
    case unknown

    static func kind(of error: Error) -> ErrorKind {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return .timeout
            case .cannotFindHost, .dnsLookupFailed: return .hostNotFound
            case .cannotConnectToHost, .networkConnectionLost: return .connectFailed
            default: return .network
            }
        }
        if error is DecodingError { return .badData }
        return .unknown
    }
}

/// 设置屏的提示条。只携带语义和参数，具体文案由 UI 翻译。
enum SettingsNotice: Equatable {
    /// 首次启动连不上，自动弹出的那句「检查地址」。
    case unreachable
    case badAddress
    case testing
    case connected(version: String?)
    case failed(ErrorKind)
}

/// 三态。服务端 `state` 只有 empty / pending / ready 三个值，但客户端仍然要兜底：
/// 字段缺失、未知值、state 和数组长度自相矛盾时，都要落到这三个之一，不能崩。
enum DayState {
    case empty
    case pending
    case ready
}

/// 标题的三种形态。domain 只负责判断「是哪一种」，具体措辞由 UI 查 strings 拼。
enum DayTitle {
    case today
    case yesterday
    /// 其他日期：月份缩写 + 日号（英文 "Nov 9"，中文 "11月9日"）。
    case other(month: String, day: Int)
}

/// 相对日期的角标同样只返回语义，文案与单复数交给 UI 的 plurals。
enum RelativeLabel {
    case tomorrow
    case daysAgo(Int)
    case inDays(Int)
}

/// 顶栏副标题的两个片段，顺序由 UI 的 header_line 模板决定（中英文语序不同）。
struct DayHeader {
    var date: String
    var weekday: String
}

/// 日期、标题、状态这些「算出来」的东西全部放在这里，纯函数。
/// 不读时钟（`today` 一律由调用方传进来），所有格式化方法都显式接收 locale。
enum DayLogic {

    // ---------- 日期 ----------

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        return c
    }

    private static func formatter(_ format: String, locale: Locale) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = TimeZone.current
        f.dateFormat = format
        return f
    }

    static func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return formatter("yyyy-MM-dd", locale: Locale(identifier: "en_US_POSIX")).date(from: raw)
            .map(startOfDay)
    }

    static func format(_ date: Date) -> String {
        formatter("yyyy-MM-dd", locale: Locale(identifier: "en_US_POSIX")).string(from: date)
    }

    /// 所在周的周一。
    static func weekStart(_ date: Date) -> Date {
        let c = calendar
        let weekday = c.component(.weekday, from: date)
        let back = (weekday + 5) % 7  // 周日=1 … 周六=7 → 距周一的天数
        return startOfDay(c.date(byAdding: .day, value: -back, to: date) ?? date)
    }

    /// 周一到周日，固定 7 天（docs/04-电视端UI.md §6：不做月历）。
    static func weekDays(_ anchor: Date) -> [Date] {
        let start = weekStart(anchor)
        return (0...6).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func clampSelectable(_ date: Date, today: Date) -> Date {
        let c = calendar
        let d = startOfDay(date)  // 跨夏令时加 7 天可能落进前一天 23 点，先归零
        let earliest = startOfDay(c.date(byAdding: .day, value: -MAX_DAYS_BACK, to: today) ?? today)
        let latest = startOfDay(c.date(byAdding: .day, value: MAX_DAYS_FORWARD, to: today) ?? today)
        return min(max(d, earliest), latest)
    }

    static func shiftDate(_ current: Date, deltaDays: Int, today: Date) -> Date {
        let next = calendar.date(byAdding: .day, value: deltaDays, to: current) ?? current
        return clampSelectable(next, today: today)
    }

    static func canGoBack(_ date: Date, today: Date) -> Bool {
        date > startOfDay(calendar.date(byAdding: .day, value: -MAX_DAYS_BACK, to: today) ?? today)
    }

    static func canGoForward(_ date: Date, today: Date) -> Bool {
        date < startOfDay(calendar.date(byAdding: .day, value: MAX_DAYS_FORWARD, to: today) ?? today)
    }

    /// 周几的短名：英文 "Thu"，中文 "周四"。
    static func weekdayShort(_ date: Date, locale: Locale) -> String {
        formatter("EEE", locale: locale).string(from: date)
    }

    /// 周几的全名：英文 "Thursday"，中文 "星期四"。
    static func weekdayLong(_ date: Date, locale: Locale) -> String {
        formatter("EEEE", locale: locale).string(from: date)
    }

    /// 单个月的缩写：英文 "Nov"，中文 "11月"（不含日号，日号由 UI 模板补）。
    static func monthShort(_ date: Date, locale: Locale) -> String {
        formatter("MMM", locale: locale).string(from: date)
    }

    static func dayNumber(_ date: Date) -> Int {
        calendar.component(.day, from: date)
    }

    /// 顶栏副标题：中文「2026年11月12日 星期四」，英文「Wed, Nov 12, 2026」。
    /// 日期用系统本地化格式，星期缩写的中英文风格不同（中文用全称，英文用短名）。
    static func header(_ date: Date, locale: Locale) -> DayHeader {
        let df = DateFormatter()
        df.locale = locale
        df.timeZone = TimeZone.current
        df.dateStyle = .medium
        df.timeStyle = .none
        let weekday = locale.language.languageCode?.identifier == "zh"
            ? weekdayLong(date, locale: locale)
            : weekdayShort(date, locale: locale)
        return DayHeader(date: df.string(from: date), weekday: weekday)
    }

    // ---------- 标题与角标 ----------

    /// 标题。`isToday` / `daysAgo` 来自服务端（协议 §6：端上时钟不一定准，
    /// 相对天数不要自己用本地时钟减），本地只在拿不到数据时兜底。
    static func titleFor(_ date: Date, isToday: Bool, daysAgo: Int?, locale: Locale) -> DayTitle {
        if isToday { return .today }
        if daysAgo == 1 { return .yesterday }
        return .other(month: monthShort(date, locale: locale), day: dayNumber(date))
    }

    /// 「3 天前」角标。今天 / 昨天不挂角标（设计稿：diff==0/1 不显示）。
    static func relativeChip(_ daysAgo: Int?) -> RelativeLabel? {
        guard let daysAgo else { return nil }
        if daysAgo == 0 || daysAgo == 1 { return nil }
        if daysAgo == -1 { return .tomorrow }
        return daysAgo < 0 ? .inDays(-daysAgo) : .daysAgo(daysAgo)
    }

    // ---------- 三态映射 ----------

    /// 把服务端 state + 数组长度映射成唯一的三态。
    /// 原则（协议 §5.1）：图是唯一可信来源。state 与数据矛盾时以图为准。
    static func effectiveState(_ raw: String?, imageCount: Int, subjectCount: Int) -> DayState {
        switch raw {
        case "ready":
            if subjectCount > 0 { return .ready }
            return imageCount > 0 ? .pending : .empty
        case "pending", "empty":
            return imageCount > 0 ? .pending : .empty
        default:
            if imageCount == 0 { return .empty }
            return subjectCount > 0 ? .ready : .pending
        }
    }

    static func effectiveState(_ day: DayView) -> DayState {
        effectiveState(day.state, imageCount: day.images.count, subjectCount: day.subjects.count)
    }

    // ---------- 取值 ----------

    static func clampIndex(_ index: Int, _ size: Int) -> Int {
        size <= 0 ? 0 : min(max(index, 0), size - 1)
    }

    /// 科目配图。没有 image_url 就退回当天第一张原图（需求：没有就保留原图）。
    static func resolveImageUrl(_ subjectImageUrl: String?, _ fallbackImageUrl: String?) -> String? {
        if let s = subjectImageUrl, !s.isEmpty { return s }
        if let f = fallbackImageUrl, !f.isEmpty { return f }
        return nil
    }

    /// 当前该显示哪张图：ready 跟科目走，pending/empty 跟图片序号走。
    static func imageFor(_ day: DayView, state: DayState, subjectIndex: Int, imageIndex: Int) -> String? {
        let first = day.images.first?.url
        switch state {
        case .ready:
            guard !day.subjects.isEmpty else { return first }
            let subject = day.subjects[clampIndex(subjectIndex, day.subjects.count)]
            return resolveImageUrl(subject.imageUrl, first)
        default:
            guard !day.images.isEmpty else { return first }
            return day.images[clampIndex(imageIndex, day.images.count)].url
        }
    }

    // ---------- 地址与时间 ----------

    /// 图片 URL 一律是相对路径（协议 §1 约定 2），客户端负责拼 base。
    /// 服务端万一给了绝对地址也照用，不二次拼接。
    static func absoluteUrl(_ baseUrl: String, _ path: String?) -> String? {
        guard let p = path, !p.isEmpty else { return nil }
        if p.lowercased().hasPrefix("http://") || p.lowercased().hasPrefix("https://") { return p }
        let base = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if base.isEmpty { return p }
        return base + (p.hasPrefix("/") ? p : "/" + p)
    }

    /// 用户可能只输入 `192.168.1.8:8080`，或者带尾斜杠。
    /// 统一成 `scheme://host[:port][/path]`，空串原样返回。
    static func normalizeServerUrl(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let lower = trimmed.lowercased()
        let withScheme: String
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            withScheme = trimmed
        } else {
            withScheme = "http://" + trimmed
        }
        return String(withScheme.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private static let urlShape = try! NSRegularExpression(
        pattern: "^https?://[^\\s/]+(:\\d+)?(/[^\\s]*)?$",
        options: [.caseInsensitive]
    )

    static func isPlausibleServerUrl(_ raw: String) -> Bool {
        let normalized = normalizeServerUrl(raw)
        guard !normalized.isEmpty else { return false }
        let range = NSRange(normalized.startIndex..., in: normalized)
        return urlShape.firstMatch(in: normalized, range: range) != nil
    }

    /// 缓存里存的 epoch 秒 → 顶栏角标用的 HH:mm。
    static func timeLabel(_ epoch: TimeInterval?) -> String? {
        guard let epoch else { return nil }
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: Date(timeIntervalSince1970: epoch))
    }

    static func nowLabel() -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: Date())
    }
}
