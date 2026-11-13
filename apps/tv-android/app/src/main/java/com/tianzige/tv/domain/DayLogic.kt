package com.tianzige.tv.domain

import com.tianzige.tv.data.DayView
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.format.TextStyle
import java.time.temporal.TemporalAdjusters
import java.util.Locale

/**
 * 三态。服务端 `state` 只有 empty / pending / ready 三个值，但客户端仍然要兜底：
 * 字段缺失、未知值、state 和数组长度自相矛盾时，都要落到这三个之一，不能崩。
 */
enum class DayState { EMPTY, PENDING, READY }

/**
 * 标题的三种形态。domain 只负责判断「是哪一种」，具体措辞由 UI 查 R.string 拼，
 * 这样纯 JVM 单测不需要 Android 资源。
 */
sealed interface DayTitle {
    data object Today : DayTitle
    data object Yesterday : DayTitle

    /** 其他日期：月份缩写 + 日号（英文 "Nov" + 9，中文 "11月" + 9）。 */
    data class Other(val month: String, val day: Int) : DayTitle
}

/** 相对日期的角标同样只返回语义，文案与单复数交给 UI 的 plurals。 */
sealed interface RelativeLabel {
    data object Tomorrow : RelativeLabel
    data class DaysAgo(val days: Int) : RelativeLabel
    data class InDays(val days: Int) : RelativeLabel
}

/** 顶栏副标题的两个片段，顺序由 UI 的 header_line 模板决定（中英文语序不同）。 */
data class DayHeader(val date: String, val weekday: String)

/**
 * 日期、标题、状态这些「算出来」的东西全部放在这里，纯函数，有单元测试。
 * 不碰 Android 框架，不读时钟（`today` 一律由调用方传进来）。
 * 所有格式化方法都显式接收 [locale]，由调用方传系统当前语言。
 */
object DayLogic {

    private val HH_MM = DateTimeFormatter.ofPattern("HH:mm", Locale.ROOT)

    // ---------- 日期 ----------

    fun parseDate(raw: String?): LocalDate? =
        raw?.let { runCatching { LocalDate.parse(it) }.getOrNull() }

    fun format(date: LocalDate): String = date.format(DateTimeFormatter.ISO_LOCAL_DATE)

    /** 所在周的周一。 */
    fun weekStart(date: LocalDate): LocalDate =
        date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))

    /** 周一到周日，固定 7 天（docs/04-电视端UI.md §6：不做月历）。 */
    fun weekDays(anchor: LocalDate): List<LocalDate> {
        val start = weekStart(anchor)
        return (0L..6L).map { start.plusDays(it) }
    }

    fun sameWeek(a: LocalDate, b: LocalDate): Boolean = weekStart(a) == weekStart(b)

    fun clampSelectable(date: LocalDate, today: LocalDate): LocalDate =
        date.coerceIn(today.minusDays(MAX_DAYS_BACK.toLong()), today.plusDays(MAX_DAYS_FORWARD.toLong()))

    fun shiftDate(current: LocalDate, deltaDays: Int, today: LocalDate): LocalDate =
        clampSelectable(current.plusDays(deltaDays.toLong()), today)

    fun canGoBack(date: LocalDate, today: LocalDate): Boolean =
        date.isAfter(today.minusDays(MAX_DAYS_BACK.toLong()))

    fun canGoForward(date: LocalDate, today: LocalDate): Boolean =
        date.isBefore(today.plusDays(MAX_DAYS_FORWARD.toLong()))

    fun weekdayShort(date: LocalDate, locale: Locale): String =
        date.dayOfWeek.getDisplayName(TextStyle.SHORT, locale)

    fun weekdayLong(date: LocalDate, locale: Locale): String =
        date.dayOfWeek.getDisplayName(TextStyle.FULL, locale)

    /** 单个月的缩写：英文 "Nov"，中文 "11月"（不含日号，日号由 UI 模板补）。 */
    fun monthShort(date: LocalDate, locale: Locale): String =
        date.month.getDisplayName(TextStyle.SHORT, locale)

    /**
     * 顶栏副标题：中文「2026年11月12日 星期四」，英文「Wed, Nov 12, 2026」。
     * 日期用系统本地化格式，星期缩写的中英文风格不同（中文用全称，英文用短名）。
     */
    fun header(date: LocalDate, locale: Locale): DayHeader {
        val dateText = date.format(
            DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale)
        )
        val weekday = if (locale.language == "zh") weekdayLong(date, locale) else weekdayShort(date, locale)
        return DayHeader(dateText, weekday)
    }

    // ---------- 标题与角标 ----------

    /**
     * 标题。`isToday` / `daysAgo` 来自服务端（协议 §6：电视系统时间经常是错的，
     * 相对天数不要自己用本地时钟减），本地只在拿不到数据时兜底。
     */
    fun titleFor(date: LocalDate, isToday: Boolean, daysAgo: Int?, locale: Locale): DayTitle = when {
        isToday -> DayTitle.Today
        daysAgo == 1 -> DayTitle.Yesterday
        else -> DayTitle.Other(monthShort(date, locale), date.dayOfMonth)
    }

    /** 「3 天前」角标。今天 / 昨天不挂角标（设计稿：diff==0/1 不显示）。 */
    fun relativeChip(daysAgo: Int?): RelativeLabel? = when {
        daysAgo == null || daysAgo == 0 || daysAgo == 1 -> null
        daysAgo == -1 -> RelativeLabel.Tomorrow
        daysAgo < 0 -> RelativeLabel.InDays(-daysAgo)
        else -> RelativeLabel.DaysAgo(daysAgo)
    }

    // ---------- 三态映射 ----------

    /**
     * 把服务端 state + 数组长度映射成唯一的三态。
     * 原则（协议 §5.1）：图是唯一可信来源。state 与数据矛盾时以图为准。
     */
    fun effectiveState(raw: String?, imageCount: Int, subjectCount: Int): DayState = when (raw) {
        "ready" -> when {
            subjectCount > 0 -> DayState.READY
            imageCount > 0 -> DayState.PENDING
            else -> DayState.EMPTY
        }
        "pending" -> if (imageCount > 0) DayState.PENDING else DayState.EMPTY
        "empty" -> if (imageCount > 0) DayState.PENDING else DayState.EMPTY
        else -> when {
            imageCount == 0 -> DayState.EMPTY
            subjectCount > 0 -> DayState.READY
            else -> DayState.PENDING
        }
    }

    fun effectiveState(day: DayView): DayState =
        effectiveState(day.state, day.images.size, day.subjects.size)

    // ---------- 取值 ----------

    fun clampIndex(index: Int, size: Int): Int = if (size <= 0) 0 else index.coerceIn(0, size - 1)

    /** 科目配图。没有 image_url 就退回当天第一张原图（需求：没有就保留原图）。 */
    fun resolveImageUrl(subjectImageUrl: String?, fallbackImageUrl: String?): String? =
        subjectImageUrl?.takeIf { it.isNotBlank() } ?: fallbackImageUrl?.takeIf { it.isNotBlank() }

    /** 当前该显示哪张图：ready 跟科目走，pending/empty 跟图片序号走。 */
    fun imageFor(day: DayView, state: DayState, subjectIndex: Int, imageIndex: Int): String? {
        val first = day.images.firstOrNull()?.url
        return when (state) {
            DayState.READY -> {
                val subject = day.subjects.getOrNull(clampIndex(subjectIndex, day.subjects.size))
                resolveImageUrl(subject?.imageUrl, first)
            }
            else -> day.images.getOrNull(clampIndex(imageIndex, day.images.size))?.url ?: first
        }
    }

    // ---------- 地址与时间 ----------

    /**
     * 图片 URL 一律是相对路径（协议 §1 约定 2），客户端负责拼 base。
     * 服务端万一给了绝对地址也照用，不二次拼接。
     */
    fun absoluteUrl(baseUrl: String, path: String?): String? {
        val p = path?.takeIf { it.isNotBlank() } ?: return null
        if (p.startsWith("http://", ignoreCase = true) || p.startsWith("https://", ignoreCase = true)) return p
        val base = baseUrl.trim().trimEnd('/')
        if (base.isEmpty()) return p
        return base + (if (p.startsWith("/")) p else "/$p")
    }

    /**
     * 用户可能只输入 `192.168.1.8:8080`，或者带尾斜杠。
     * 统一成 `scheme://host[:port][/path]`，空串原样返回。
     */
    fun normalizeServerUrl(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return ""
        val withScheme = when {
            trimmed.startsWith("http://", ignoreCase = true) -> trimmed
            trimmed.startsWith("https://", ignoreCase = true) -> trimmed
            else -> "http://$trimmed"
        }
        return withScheme.trimEnd('/')
    }

    private val URL_SHAPE = Regex("^https?://[^\\s/]+(:\\d+)?(/[^\\s]*)?$", RegexOption.IGNORE_CASE)

    fun isPlausibleServerUrl(raw: String): Boolean {
        val normalized = normalizeServerUrl(raw)
        return normalized.isNotEmpty() && URL_SHAPE.matches(normalized)
    }

    /** 缓存文件里的 ISO 时间 → 顶栏角标用的 HH:mm。 */
    fun timeLabel(isoLocalDateTime: String?): String? =
        isoLocalDateTime?.let {
            runCatching { LocalDateTime.parse(it).format(HH_MM) }.getOrNull()
        }

    fun nowLabel(): String = LocalDateTime.now().format(HH_MM)
}
