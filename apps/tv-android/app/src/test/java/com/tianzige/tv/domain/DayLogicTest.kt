package com.tianzige.tv.domain

import com.tianzige.tv.data.DayView
import com.tianzige.tv.data.ImageRef
import com.tianzige.tv.data.SubjectGroup
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.DayOfWeek
import java.time.LocalDate
import java.util.Locale

/**
 * 状态机映射、日期计算这类「算出来的东西」全部是纯函数，这里逐个钉死。
 * 普通 JVM JUnit，不需要 Robolectric。
 */
class DayLogicTest {

    private val today = LocalDate.of(2026, 11, 12) // 星期四

    // ---------------------------------------------------------------- 日期

    @Test
    fun `weekStart 返回所在周的周一`() {
        assertEquals(LocalDate.of(2026, 11, 9), DayLogic.weekStart(today))
    }

    @Test
    fun `周日属于同一周而不是下一周`() {
        val sunday = LocalDate.of(2026, 11, 15)
        assertEquals(DayOfWeek.SUNDAY, sunday.dayOfWeek)
        assertEquals(LocalDate.of(2026, 11, 9), DayLogic.weekStart(sunday))
    }

    @Test
    fun `weekDays 固定周一到周日七天`() {
        val days = DayLogic.weekDays(today)
        assertEquals(7, days.size)
        assertEquals(DayOfWeek.MONDAY, days.first().dayOfWeek)
        assertEquals(DayOfWeek.SUNDAY, days.last().dayOfWeek)
        assertEquals(LocalDate.of(2026, 11, 9), days.first())
        assertEquals(LocalDate.of(2026, 11, 15), days.last())
    }

    @Test
    fun `往前翻一天会跨周，周起始同步变化`() {
        val monday = LocalDate.of(2026, 11, 9)
        val previous = DayLogic.shiftDate(monday, -1, today)
        assertEquals(LocalDate.of(2026, 11, 8), previous)
        assertEquals(LocalDate.of(2026, 11, 2), DayLogic.weekStart(previous))
        assertFalse(DayLogic.sameWeek(monday, previous))
    }

    @Test
    fun `最多回看 56 天、最多前看 6 天`() {
        assertEquals(LocalDate.of(2026, 9, 17), DayLogic.shiftDate(today, -1000, today))
        assertEquals(LocalDate.of(2026, 11, 18), DayLogic.shiftDate(today, 1000, today))
        assertTrue(DayLogic.canGoBack(today, today))
        assertTrue(DayLogic.canGoForward(today, today))
        assertFalse(DayLogic.canGoBack(today.minusDays(56), today))
        assertFalse(DayLogic.canGoForward(today.plusDays(6), today))
    }

    @Test
    fun `顶栏副标题带年月日和星期`() {
        assertEquals(DayHeader("2026年11月12日", "星期四"), DayLogic.header(today, Locale.CHINA))
        assertEquals("周四", DayLogic.weekdayShort(today, Locale.CHINA))
        assertEquals("星期四", DayLogic.weekdayLong(today, Locale.CHINA))
    }

    @Test
    fun `英文环境顶栏用英文日期和星期缩写`() {
        assertEquals(DayHeader("Nov 12, 2026", "Thu"), DayLogic.header(today, Locale.ENGLISH))
        assertEquals("Thu", DayLogic.weekdayShort(today, Locale.ENGLISH))
    }

    // ---------------------------------------------------------------- 标题

    @Test
    fun `今天的标题`() {
        assertEquals(DayTitle.Today, DayLogic.titleFor(today, isToday = true, daysAgo = 0, Locale.ENGLISH))
    }

    @Test
    fun `昨天的标题`() {
        assertEquals(
            DayTitle.Yesterday,
            DayLogic.titleFor(today.minusDays(1), isToday = false, daysAgo = 1, Locale.CHINA),
        )
    }

    @Test
    fun `更早的日期用几月几日`() {
        assertEquals(
            DayTitle.Other("11月", 9),
            DayLogic.titleFor(LocalDate.of(2026, 11, 9), isToday = false, daysAgo = 3, locale = Locale.CHINA),
        )
        assertEquals(
            DayTitle.Other("Nov", 9),
            DayLogic.titleFor(LocalDate.of(2026, 11, 9), isToday = false, daysAgo = 3, locale = Locale.ENGLISH),
        )
    }

    @Test
    fun `未来日期也能显示`() {
        assertEquals(
            DayTitle.Other("11月", 18),
            DayLogic.titleFor(LocalDate.of(2026, 11, 18), isToday = false, daysAgo = -6, locale = Locale.CHINA),
        )
        assertEquals(RelativeLabel.Tomorrow, DayLogic.relativeChip(-1))
        assertEquals(RelativeLabel.InDays(6), DayLogic.relativeChip(-6))
    }

    @Test
    fun `角标只在天数大于 1 时出现`() {
        assertNull(DayLogic.relativeChip(null))
        assertNull(DayLogic.relativeChip(0))
        assertNull(DayLogic.relativeChip(1))
        assertEquals(RelativeLabel.DaysAgo(2), DayLogic.relativeChip(2))
        assertEquals(RelativeLabel.DaysAgo(31), DayLogic.relativeChip(31))
    }

    // ---------------------------------------------------------------- 三态

    @Test
    fun `ready 有科目就是 ready`() {
        assertEquals(DayState.READY, DayLogic.effectiveState("ready", imageCount = 2, subjectCount = 3))
    }

    @Test
    fun `ready 但科目为空退化成 pending`() {
        assertEquals(DayState.PENDING, DayLogic.effectiveState("ready", imageCount = 2, subjectCount = 0))
    }

    @Test
    fun `pending 没有图就是 empty`() {
        assertEquals(DayState.EMPTY, DayLogic.effectiveState("pending", imageCount = 0, subjectCount = 0))
    }

    @Test
    fun `empty 但有图按 pending 处理 图是准的`() {
        assertEquals(DayState.PENDING, DayLogic.effectiveState("empty", imageCount = 1, subjectCount = 0))
    }

    @Test
    fun `未知 state 按数组长度猜`() {
        assertEquals(DayState.EMPTY, DayLogic.effectiveState("whatever", imageCount = 0, subjectCount = 0))
        assertEquals(DayState.READY, DayLogic.effectiveState(null, imageCount = 1, subjectCount = 1))
        assertEquals(DayState.PENDING, DayLogic.effectiveState("", imageCount = 3, subjectCount = 0))
    }

    // ---------------------------------------------------------------- 取图

    @Test
    fun `科目没有配图就退回当天第一张原图`() {
        assertEquals("/img/a.jpg", DayLogic.resolveImageUrl("/img/a.jpg", "/img/b.jpg"))
        assertEquals("/img/b.jpg", DayLogic.resolveImageUrl(null, "/img/b.jpg"))
        assertEquals("/img/b.jpg", DayLogic.resolveImageUrl("  ", "/img/b.jpg"))
        assertNull(DayLogic.resolveImageUrl(null, null))
    }

    @Test
    fun `ready 时按科目取图`() {
        val day = DayView(
            date = "2026-11-12",
            state = "ready",
            images = listOf(ImageRef(url = "/img/1.jpg"), ImageRef(url = "/img/2.jpg")),
            subjects = listOf(
                SubjectGroup(subject = "语文", imageUrl = "/img/1.jpg"),
                SubjectGroup(subject = "数学", imageUrl = "/img/2.jpg"),
                SubjectGroup(subject = "英语", imageUrl = null),
            ),
        )
        assertEquals("/img/1.jpg", DayLogic.imageFor(day, DayState.READY, 0, 0))
        assertEquals("/img/2.jpg", DayLogic.imageFor(day, DayState.READY, 1, 0))
        assertEquals("/img/1.jpg", DayLogic.imageFor(day, DayState.READY, 2, 0))
    }

    @Test
    fun `pending 时按图片序号取图`() {
        val day = DayView(
            state = "pending",
            images = listOf(ImageRef(url = "/img/1.jpg"), ImageRef(url = "/img/2.jpg")),
        )
        assertEquals("/img/2.jpg", DayLogic.imageFor(day, DayState.PENDING, 0, 1))
        assertEquals("/img/2.jpg", DayLogic.imageFor(day, DayState.PENDING, 0, 99))
        assertNull(DayLogic.imageFor(day.copy(images = emptyList()), DayState.EMPTY, 0, 0))
    }

    @Test
    fun `下标越界自动夹到边界`() {
        assertEquals(0, DayLogic.clampIndex(0, 0))
        assertEquals(0, DayLogic.clampIndex(-3, 5))
        assertEquals(4, DayLogic.clampIndex(9, 5))
        assertEquals(2, DayLogic.clampIndex(2, 5))
    }

    // ---------------------------------------------------------------- 地址与时间

    @Test
    fun `地址缺协议时补 http`() {
        assertEquals("http://192.168.1.8:8080", DayLogic.normalizeServerUrl("192.168.1.8:8080"))
        assertEquals("http://nas.local:8080", DayLogic.normalizeServerUrl("  http://nas.local:8080/  "))
        assertEquals("https://a.b", DayLogic.normalizeServerUrl("https://a.b/"))
        assertEquals("", DayLogic.normalizeServerUrl("   "))
    }

    @Test
    fun `地址合法性检查`() {
        assertTrue(DayLogic.isPlausibleServerUrl("192.168.1.8:8080"))
        assertTrue(DayLogic.isPlausibleServerUrl("http://nas.local:8080"))
        assertFalse(DayLogic.isPlausibleServerUrl(""))
        assertFalse(DayLogic.isPlausibleServerUrl("http://"))
        assertFalse(DayLogic.isPlausibleServerUrl("192.168.1.8:8080 extra"))
    }

    @Test
    fun `图片相对路径拼上服务端地址`() {
        assertEquals("http://192.168.1.8:8080/img/2026-11-12/1.jpg", DayLogic.absoluteUrl("http://192.168.1.8:8080/", "/img/2026-11-12/1.jpg"))
        assertEquals("http://nas.local:8080/img/a.jpg", DayLogic.absoluteUrl("http://nas.local:8080", "img/a.jpg"))
        assertEquals("https://cdn.example.com/x.jpg", DayLogic.absoluteUrl("http://nas.local:8080", "https://cdn.example.com/x.jpg"))
        assertNull(DayLogic.absoluteUrl("http://nas.local:8080", null))
        assertNull(DayLogic.absoluteUrl("http://nas.local:8080", "  "))
    }

    @Test
    fun `缓存时间格式化成时分`() {
        assertEquals("17:32", DayLogic.timeLabel("2026-11-12T17:32:11.123"))
        assertNull(DayLogic.timeLabel("不是时间"))
        assertNull(DayLogic.timeLabel(null))
    }

    @Test
    fun `日期解析坏数据返回 null`() {
        assertEquals(today, DayLogic.parseDate("2026-11-12"))
        assertNull(DayLogic.parseDate("2026/11/12"))
        assertNull(DayLogic.parseDate(null))
    }
}
