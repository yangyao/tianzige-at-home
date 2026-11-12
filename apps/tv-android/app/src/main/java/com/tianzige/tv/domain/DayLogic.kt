package com.tianzige.tv.domain

import com.tianzige.tv.data.DayView
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters
import java.util.Locale

/**
 * 三态。服务端 `state` 只有 empty / pending / ready 三个值，但客户端仍然要兜底：
 * 字段缺失、未知值、state 和数组长度自相矛盾时，都要落到这三个之一，不能崩。
 */
enum class DayState { EMPTY, PENDING, READY }

/**
 * 日期、标题、状态这些「算出来」的东西全部放在这里，纯函数，有单元测试。
 * 不碰 Android 框架，不读时钟（`today` 一律由调用方传进来）。
 */
object DayLogic {

    private val WEEKDAY_LONG = listOf("星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日")
    private val WEEKDAY_SHORT = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
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

    fun weekdayShort(date: LocalDate): String = WEEKDAY_SHORT[date.dayOfWeek.value - 1]

    fun weekdayLong(date: LocalDate): String = WEEKDAY_LONG[date.dayOfWeek.value - 1]

    /** 顶栏副标题：2026年11月12日 星期四 */
    fun headerLine(date: LocalDate): String =
        "${date.year}年${date.monthValue}月${date.dayOfMonth}日 ${weekdayLong(date)}"

    // ---------- 标题与角标 ----------

    /**
     * 标题。`isToday` / `daysAgo` 来自服务端（协议 §6：电视系统时间经常是错的，
     * 相对天数不要自己用本地时钟减），本地只在拿不到数据时兜底。
     */
    fun titleFor(date: LocalDate, isToday: Boolean, daysAgo: Int?): String = when {
        isToday -> "今天的作业"
        daysAgo == 1 -> "昨天的作业"
        else -> "${date.monthValue}月${date.dayOfMonth}日的作业"
    }

    /** 「3 天前」角标。今天 / 昨天不挂角标（设计稿：diff==0/1 不显示）。 */
    fun relativeChip(daysAgo: Int?): String? = when {
        daysAgo == null || daysAgo == 0 || daysAgo == 1 -> null
        daysAgo < 0 -> if (daysAgo == -1) "明天" else "${-daysAgo} 天后"
        else -> "$daysAgo 天前"
    }

    /** 空状态主文案。今天用规范原句，历史日期换成「这天」。 */
    fun emptyTitle(isToday: Boolean): String = if (isToday) "今天还没有作业" else "这天还没有作业"

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
