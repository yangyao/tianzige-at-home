package com.tianzige.tv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.type
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.material3.Text
import com.tianzige.tv.domain.DayLogic
import com.tianzige.tv.ui.components.TvFocusable
import com.tianzige.tv.ui.theme.Accent
import com.tianzige.tv.ui.theme.BgRaised
import com.tianzige.tv.ui.theme.BgSurface
import com.tianzige.tv.ui.theme.Flower
import com.tianzige.tv.ui.theme.LocalTz
import com.tianzige.tv.ui.theme.TextDim
import com.tianzige.tv.ui.theme.TextPrimary
import com.tianzige.tv.ui.theme.TextSecondary
import com.tianzige.tv.vm.HomeUiState
import java.time.LocalDate

/**
 * 本周 7 天横条（docs/04-电视端UI.md §6：不做月历）。
 * 有作业的日子挂 flower 圆点，圆点数据来自 /api/days，一次取一周。
 */
@Composable
fun DateStrip(
    state: HomeUiState,
    selectedRequester: FocusRequester,
    onSelectDate: (LocalDate) -> Unit,
) {
    val dims = LocalTz.current.dimens
    val days = remember(state.selectedDate) { DayLogic.weekDays(state.selectedDate) }
    val canBack = DayLogic.canGoBack(state.selectedDate, state.today)
    val canForward = DayLogic.canGoForward(state.selectedDate, state.today)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(dims.dp(104f)),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dims.dp(14f)),
    ) {
        Chevron(glyph = "‹", enabled = canBack, onActivate = { onSelectDate(state.selectedDate.minusWeeks(1)) })
        days.forEach { date ->
            val selected = date == state.selectedDate
            DayCard(
                date = date,
                onSelect = { onSelectDate(date) },
                selected = selected,
                isToday = date == state.today,
                hasWork = state.marks[DayLogic.format(date)]?.has == true,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .then(if (selected) Modifier.focusRequester(selectedRequester) else Modifier),
            )
        }
        Chevron(glyph = "›", enabled = canForward, onActivate = { onSelectDate(state.selectedDate.plusWeeks(1)) })
    }
}

@Composable
private fun Chevron(glyph: String, enabled: Boolean, onActivate: () -> Unit) {
    val tz = LocalTz.current
    val dims = tz.dimens
    var focused by remember { mutableStateOf(false) }
    Text(
        text = glyph,
        style = tz.type.h1,
        color = if (focused) Accent else if (enabled) TextSecondary else TextDim.copy(alpha = 0.35f),
        modifier = Modifier.width(dims.dp(40f)).onFocusChanged { focused = it.isFocused }.onKeyEvent {
            if (it.type == KeyEventType.KeyDown && it.nativeKeyEvent.keyCode in listOf(23, 66)) { onActivate(); true } else false
        }.focusable(enabled),
        textAlign = TextAlign.Center,
        maxLines = 1,
    )
}

@Composable
private fun DayCard(
    date: LocalDate,
    onSelect: () -> Unit,
    selected: Boolean,
    isToday: Boolean,
    hasWork: Boolean,
    modifier: Modifier,
) {
    val tz = LocalTz.current
    val dims = tz.dimens

    var focused by remember { mutableStateOf(false) }
    TvFocusable(
        focused = focused,
        modifier = modifier.onFocusChanged {
            focused = it.isFocused
            if (it.isFocused) onSelect()
        }.focusable(),
        corner = dims.dp(16f),
        background = if (isToday) BgRaised else BgSurface,
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                text = DayLogic.weekdayShort(date),
                style = tz.type.min,
                color = if (isToday) TextSecondary else TextDim,
                maxLines = 1,
            )
            Text(
                text = date.dayOfMonth.toString(),
                style = tz.type.dateNumber,
                color = if (selected) Accent else TextPrimary,
                maxLines = 1,
            )
        }
        if (hasWork) {
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = dims.dp(12f), end = dims.dp(14f))
                    .size(dims.dp(11f))
                    .clip(CircleShape)
                    .background(Flower)
            )
        }
    }
}
