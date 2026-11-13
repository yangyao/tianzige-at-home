import Foundation

/// 协议要求：日期字符串一律 `YYYY-MM-DD`，语义是 **Asia/Shanghai 的那一天**。
/// 不用设备时区，避免晚上 23:50 上传被算成第二天。
enum DateString {
    static let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone.current

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static let apiFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// 行内展示用：英文 `Nov 9`，中文 `11月9日`。
    /// 由系统按当前语言给出模板（`MMMd`），不手拼「M月d日」——手拼的英文环境会露馅。
    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    static func apiDate(from date: Date) -> String {
        apiFormatter.string(from: date)
    }

    /// 上海时区的今天零点，作为日期选择器的默认值。
    static var today: Date {
        calendar.startOfDay(for: Date())
    }

    /// 允许往前补传 7 天（协议 §6：补传昨天的作业是真实需求）。
    static var earliestSelectableDay: Date {
        calendar.date(byAdding: .day, value: -7, to: today) ?? today
    }

    /// 行内展示用：今天 / 昨天 / 11月10日
    static func dayLabel(for date: Date) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: today
        ).day ?? 0

        switch days {
        case 0: return L10n.string("date.today")
        case 1: return L10n.string("date.yesterday")
        default: return monthDayFormatter.string(from: date)
        }
    }
}
