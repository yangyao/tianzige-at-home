import Foundation

/// domain 只返回语义（今天是哪种标题、哪类错误），真正的文案在这里换成 strings。
/// 语言取系统配置，不做应用内切换（docs/12-国际化.md §1）。
enum Texts {

    static var locale: Locale { .current }

    /// 「2026年11月12日 星期四」/「Thu, Nov 12, 2026」。
    static func header(_ date: Date) -> String {
        let h = DayLogic.header(date, locale: locale)
        return L10n.format("header_line", h.date, h.weekday)
    }

    /// 「今天的作业」/「11月9日的作业」/「Homework for Nov 9」。
    static func dayTitle(_ date: Date, isToday: Bool, daysAgo: Int?) -> String {
        switch DayLogic.titleFor(date, isToday: isToday, daysAgo: daysAgo, locale: locale) {
        case .today: return L10n.string("title_today")
        case .yesterday: return L10n.string("title_yesterday")
        case let .other(month, day):
            return L10n.format("title_date", L10n.format("date_short", month, day))
        }
    }

    /// 科目名：中文环境原样，英文环境查表，未知科目原样。
    static func subject(_ raw: String) -> String {
        SubjectNames.display(raw, locale: locale)
    }

    static func errorText(_ kind: ErrorKind) -> String {
        L10n.string(kind.key)
    }

    static func noticeText(_ notice: SettingsNotice) -> String {
        switch notice {
        case .unreachable: return L10n.string("notice_unreachable")
        case .badAddress: return L10n.string("notice_bad_address")
        case .testing: return L10n.string("notice_testing")
        case let .connected(version):
            return L10n.format("notice_connected", version ?? L10n.string("notice_version_unknown"))
        case let .failed(kind):
            return L10n.format("notice_failed", errorText(kind))
        }
    }
}

extension ErrorKind {
    var key: String {
        switch self {
        case .timeout: return "error_timeout"
        case .hostNotFound: return "error_host"
        case .connectFailed: return "error_connect"
        case .badData: return "error_data"
        case .badAddress: return "error_address"
        case .network: return "error_network"
        case .unknown: return "error_unknown"
        }
    }
}
