package com.tianzige.tv.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsPadTest {

    @Test
    fun `网格是 5 行 3 列`() {
        assertEquals(5, SettingsPad.ROW_COUNT)
        assertEquals(3, SettingsPad.COL_COUNT)
        assertEquals(4, SettingsPad.keyRows.size)
        assertEquals(3, SettingsPad.actions.size)
        assertEquals("1", SettingsPad.label(0, 0))
        assertEquals("0", SettingsPad.label(3, 1))
        assertEquals(SettingsPad.BACKSPACE, SettingsPad.label(3, 2))
        assertEquals("保存", SettingsPad.label(SettingsPad.ACTION_ROW, 0))
    }

    @Test
    fun `移动时贴边不循环`() {
        assertEquals(0 to 0, SettingsPad.move(0, 0, -1, -1))
        assertEquals(4 to 2, SettingsPad.move(4, 2, 1, 1))
        assertEquals(2 to 1, SettingsPad.move(1, 0, 1, 1))
    }

    @Test
    fun `输入与退格`() {
        assertEquals("192.168", SettingsPad.append("192.16", "8"))
        assertEquals("192.16", SettingsPad.append("192.168", SettingsPad.BACKSPACE))
        assertEquals("", SettingsPad.append("", SettingsPad.BACKSPACE))
    }

    @Test
    fun `长度上限保护`() {
        val long = "1".repeat(SettingsPad.MAX_LENGTH)
        assertEquals(long, SettingsPad.append(long, "2"))
        assertTrue(SettingsPad.append(long, "2").length == SettingsPad.MAX_LENGTH)
    }
}
