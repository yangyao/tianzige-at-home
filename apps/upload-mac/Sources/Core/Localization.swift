import Foundation

/// 界面文案的唯一入口。key 见 `Resources/en.lproj|zh-Hans.lproj/Localizable.strings`。
///
/// 用 `NSLocalizedString` 而不是 `String(localized:)`：错误码映射这类 key 是运行时拼的，
/// 后者只吃字符串字面量。
enum L10n {

    /// 无参数文案。
    static func string(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    /// 带参数文案，占位符用 `%1$d` / `%1$@`。
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
    }

    /// 英文要区分 1 photo / 3 photos。数量为 1 走 `one` key，其余走带 `%1$d` 的那条。
    static func count(_ value: Int, one key: String, other otherKey: String) -> String {
        value == 1 ? string(key) : format(otherKey, value)
    }
}
