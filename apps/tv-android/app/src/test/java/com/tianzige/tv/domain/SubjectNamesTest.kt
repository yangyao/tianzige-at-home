package com.tianzige.tv.domain

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Locale

/**
 * 科目名只在显示层翻译（docs/12-国际化.md §4）：
 * 中文原样、英文查表、查不到原样，绝不出现 Unknown。
 */
class SubjectNamesTest {

    @Test
    fun `英文环境翻译已知科目`() {
        assertEquals("Chinese", SubjectNames.display("语文", Locale.ENGLISH))
        assertEquals("Math", SubjectNames.display("数学", Locale.ENGLISH))
        assertEquals("English", SubjectNames.display("英语", Locale.ENGLISH))
        assertEquals("Science", SubjectNames.display("科学", Locale.ENGLISH))
        assertEquals("Civics", SubjectNames.display("道法", Locale.ENGLISH))
        assertEquals("Other", SubjectNames.display("其他", Locale.ENGLISH))
    }

    @Test
    fun `中文环境原样显示`() {
        assertEquals("语文", SubjectNames.display("语文", Locale.CHINA))
        assertEquals("道法", SubjectNames.display("道法", Locale.CHINA))
        assertEquals("美术", SubjectNames.display("美术", Locale.CHINA))
    }

    @Test
    fun `查不到的科目原样返回中文`() {
        assertEquals("美术", SubjectNames.display("美术", Locale.ENGLISH))
        assertEquals("体育", SubjectNames.display("体育", Locale.ENGLISH))
        assertEquals("", SubjectNames.display("", Locale.ENGLISH))
    }

    @Test
    fun `非中文的其他语言也走英文表`() {
        assertEquals("Math", SubjectNames.display("数学", Locale.GERMANY))
        assertEquals("美术", SubjectNames.display("美术", Locale.JAPAN))
    }
}
