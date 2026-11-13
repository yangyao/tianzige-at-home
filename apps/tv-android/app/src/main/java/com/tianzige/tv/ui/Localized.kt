package com.tianzige.tv.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import com.tianzige.tv.R
import com.tianzige.tv.domain.DayLogic
import com.tianzige.tv.domain.DayTitle
import com.tianzige.tv.domain.ErrorKind
import com.tianzige.tv.domain.PadAction
import com.tianzige.tv.domain.SettingsNotice
import com.tianzige.tv.domain.SubjectNames
import java.time.LocalDate
import java.util.Locale

/**
 * domain 只返回语义（今天是哪种标题、哪类错误），真正的文案在这里换成 R.string。
 * 语言取系统配置，不做应用内切换（docs/12-国际化.md §1）。
 */
@Composable
fun currentLocale(): Locale = LocalConfiguration.current.locales[0]

/** 「2026年11月12日 星期四」/「Wed, Nov 12, 2026」。 */
@Composable
fun headerText(date: LocalDate): String {
    val header = DayLogic.header(date, currentLocale())
    return stringResource(R.string.header_line, header.date, header.weekday)
}

/** 「今天的作业」/「11月9日的作业」/「Homework for Nov 9」。 */
@Composable
fun dayTitleText(date: LocalDate, isToday: Boolean, daysAgo: Int?): String =
    when (val title = DayLogic.titleFor(date, isToday, daysAgo, currentLocale())) {
        DayTitle.Today -> stringResource(R.string.title_today)
        DayTitle.Yesterday -> stringResource(R.string.title_yesterday)
        is DayTitle.Other -> stringResource(
            R.string.title_date,
            stringResource(R.string.date_short, title.month, title.day),
        )
    }

@Composable
fun weekdayShortText(date: LocalDate): String =
    DayLogic.weekdayShort(date, currentLocale())

/** 科目名：中文环境原样，英文环境查表，未知科目原样。 */
@Composable
fun subjectText(raw: String): String = SubjectNames.display(raw, currentLocale())

@Composable
fun errorKindText(kind: ErrorKind): String = stringResource(
    when (kind) {
        ErrorKind.TIMEOUT -> R.string.error_timeout
        ErrorKind.HOST_NOT_FOUND -> R.string.error_host
        ErrorKind.CONNECT_FAILED -> R.string.error_connect
        ErrorKind.BAD_DATA -> R.string.error_data
        ErrorKind.BAD_ADDRESS -> R.string.error_address
        ErrorKind.NETWORK -> R.string.error_network
        ErrorKind.UNKNOWN -> R.string.error_unknown
    }
)

@Composable
fun settingsNoticeText(notice: SettingsNotice): String = when (notice) {
    SettingsNotice.Unreachable -> stringResource(R.string.notice_unreachable)
    SettingsNotice.BadAddress -> stringResource(R.string.notice_bad_address)
    SettingsNotice.Testing -> stringResource(R.string.notice_testing)
    is SettingsNotice.Connected -> stringResource(
        R.string.notice_connected,
        notice.version ?: stringResource(R.string.notice_version_unknown),
    )
    is SettingsNotice.Failed -> stringResource(R.string.notice_failed, errorKindText(notice.kind))
}

@Composable
fun padActionText(action: PadAction): String = stringResource(
    when (action) {
        PadAction.SAVE -> R.string.save
        PadAction.TEST -> R.string.test_connection
        PadAction.CLEAR -> R.string.clear
    }
)
