package com.tianzige.tv.domain

/** 设置屏第 5 行的三个动作。显示文案在 UI 层查 R.string。 */
enum class PadAction { SAVE, TEST, CLEAR }

/**
 * 设置屏的「IP 数字键盘」。遥控器没有键盘，只能一排排按键选。
 * 前 4 行是输入键，第 5 行是动作键 —— 正好构成 5×3 的网格，方向键逻辑极简。
 */
object SettingsPad {

    const val BACKSPACE = "⌫"

    val keyRows: List<List<String>> = listOf(
        listOf("1", "2", "3"),
        listOf("4", "5", "6"),
        listOf("7", "8", "9"),
        listOf(".", "0", BACKSPACE),
    )

    val actions: List<PadAction> = listOf(PadAction.SAVE, PadAction.TEST, PadAction.CLEAR)

    const val ACTION_ROW = 4
    const val ROW_COUNT = 5
    const val COL_COUNT = 3
    const val MAX_LENGTH = 48

    /** 只对输入行有效：取 0-9 / . / ⌫ 的按键字符。 */
    fun keyLabel(row: Int, col: Int): String = keyRows[row][col]

    fun actionAt(col: Int): PadAction = actions[col]

    fun isInputRow(row: Int): Boolean = row in keyRows.indices

    /** 在网格里移动，越界就贴边（不做循环，孩子按过头能原路退回来）。 */
    fun move(row: Int, col: Int, dRow: Int, dCol: Int): Pair<Int, Int> =
        (row + dRow).coerceIn(0, ROW_COUNT - 1) to (col + dCol).coerceIn(0, COL_COUNT - 1)

    fun append(current: String, key: String): String =
        if (key == BACKSPACE) dropLast(current) else if (current.length >= MAX_LENGTH) current else current + key

    fun dropLast(current: String): String = if (current.isEmpty()) current else current.substring(0, current.length - 1)
}
