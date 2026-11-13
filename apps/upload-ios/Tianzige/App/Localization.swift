import Foundation

/// 界面文案的唯一入口。key 见 `Resources/en.lproj|zh-Hans.lproj/Localizable.strings`。
///
/// 为什么不用 `String(localized:)`：这里的 key 是运行时拼出来的语义名（如错误码映射），
/// 那个 API 只吃字符串字面量。`NSLocalizedString` 两种场景都能用，语义也直白。
enum L10n {

    /// 无参数文案。
    static func string(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    /// 带参数文案。strings 文件里用 `%1$d` / `%1$@` 占位，参数顺序与占位符对应。
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
    }

    /// 英文要区分 1 photo / 3 photos。数量为 1 时走 `one` key，其余走带 `%1$d` 的那条。
    /// 中文两条都在 strings 里写全，调用方不需要关心语言。
    static func count(_ value: Int, one key: String, other otherKey: String) -> String {
        value == 1 ? string(key) : format(otherKey, value)
    }
}
