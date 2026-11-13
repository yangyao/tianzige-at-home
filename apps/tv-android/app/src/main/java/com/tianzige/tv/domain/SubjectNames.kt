package com.tianzige.tv.domain

import java.util.Locale

/**
 * 服务端存的科目名是中文（docs/12-国际化.md §4），只在显示层翻译。
 * 中文环境原样返回；英文环境查表；查不到（老师写了「美术」之类）也原样返回，
 * 绝不显示 "Unknown"。服务端返回值本身不能动：科目名参与 checkin 的主键。
 */
object SubjectNames {

    private val EN: Map<String, String> = mapOf(
        "语文" to "Chinese",
        "数学" to "Math",
        "英语" to "English",
        "科学" to "Science",
        "道法" to "Civics",
        "其他" to "Other",
    )

    fun display(raw: String, locale: Locale): String =
        if (locale.language == "zh") raw else EN[raw] ?: raw
}
