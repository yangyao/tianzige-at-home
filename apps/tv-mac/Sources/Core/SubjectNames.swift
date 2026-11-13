import Foundation

/// 服务端存的科目名是中文（docs/12-国际化.md §4），只在显示层翻译。
/// 中文环境原样返回；英文环境查表；查不到（老师写了「美术」之类）也原样返回，
/// 绝不显示 "Unknown"。服务端返回值本身不能动：科目名参与 checkin 的主键。
enum SubjectNames {
    private static let en: [String: String] = [
        "语文": "Chinese",
        "数学": "Math",
        "英语": "English",
        "科学": "Science",
        "道法": "Civics",
        "其他": "Other",
    ]

    static func display(_ raw: String, locale: Locale) -> String {
        if locale.language.languageCode?.identifier == "zh" { return raw }
        return en[raw] ?? raw
    }
}
