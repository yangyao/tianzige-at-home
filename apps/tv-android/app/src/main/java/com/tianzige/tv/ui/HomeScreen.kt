package com.tianzige.tv.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.material3.Text
import com.tianzige.tv.domain.DayLogic
import com.tianzige.tv.domain.DayState
import com.tianzige.tv.ui.components.Chip
import com.tianzige.tv.ui.components.KeyHint
import com.tianzige.tv.ui.theme.Accent
import com.tianzige.tv.ui.theme.Flower
import com.tianzige.tv.ui.theme.LocalTz
import com.tianzige.tv.ui.theme.TextDim
import com.tianzige.tv.ui.theme.TextPrimary
import com.tianzige.tv.ui.theme.TextSecondary
import com.tianzige.tv.ui.theme.Warn
import com.tianzige.tv.vm.HomeUiState

/** 首屏展示当天全部学科；日期与照片参与原生焦点导航，屏幕不常驻操作说明。 */
@Composable
fun HomeScreen(state: HomeUiState, vm: com.tianzige.tv.vm.HomeViewModel) {
    val dims = LocalTz.current.dimens
    val cardFocus = remember { FocusRequester() }

    // 让系统焦点跟着选中日期走；键位由根节点统一拦截，焦点搜索不会乱跑
    LaunchedEffect(state.selectedDate) {
        runCatching { cardFocus.requestFocus() }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(start = dims.dp(60f), end = dims.dp(60f), top = dims.dp(48f)),
    ) {
        TopBar(state)
        Spacer(Modifier.height(dims.dp(26f)))
        DateStrip(state = state, selectedRequester = cardFocus, onSelectDate = vm::selectDate)
        Spacer(Modifier.height(dims.dp(30f)))
        Content(state = state, vm = vm, modifier = Modifier.weight(1f).padding(bottom = dims.dp(48f)))
    }
}

@Composable
private fun TopBar(state: HomeUiState) {
    val tz = LocalTz.current
    val dims = tz.dimens
    val date = state.selectedDate
    val key = DayLogic.format(date)
    val serverDay = state.day?.takeIf { it.date == key }
    val isToday = date == state.today
    val chip = DayLogic.relativeChip(serverDay?.daysAgo)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(dims.dp(96f)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = DayLogic.titleFor(date, isToday, serverDay?.daysAgo),
            style = tz.type.h1,
            color = TextPrimary,
            maxLines = 1,
        )
        Spacer(Modifier.width(dims.dp(28f)))
        Text(
            text = DayLogic.headerLine(date),
            style = tz.type.body,
            color = TextSecondary,
            maxLines = 1,
        )
        Spacer(Modifier.weight(1f))

    }
}

@Composable
private fun Content(state: HomeUiState, vm: com.tianzige.tv.vm.HomeViewModel, modifier: Modifier) {
    val day = state.day
    Box(modifier = modifier.fillMaxWidth()) {
        when {
            day == null && state.dayLoading -> LoadingPanel()
            day == null -> ErrorPanel(state)
            state.dayState() == DayState.EMPTY -> EmptyPanel(isToday = state.selectedDate == state.today)
            state.dayState() == DayState.PENDING -> PendingPanel(day = day, imageIndex = state.imageIndex, baseUrl = state.serverUrl, vm = vm)
            else -> ReadyPanel(day = day, baseUrl = state.serverUrl, vm = vm)
        }
    }
}

@Composable
private fun LoadingPanel() {
    val tz = LocalTz.current
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text("正在打开今天的作业…", style = tz.type.body, color = TextDim)
    }
}

@Composable
private fun ErrorPanel(state: HomeUiState) {
    val tz = LocalTz.current
    val dims = tz.dimens
    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("连不上家里", style = tz.type.h1, color = TextPrimary)
        Spacer(Modifier.height(dims.dp(20f)))
        Text(text = state.fatalError ?: "网络好像不通", style = tz.type.body, color = TextSecondary)
        Spacer(Modifier.height(dims.dp(10f)))
        Text(text = state.serverUrl, style = tz.type.caption, color = TextDim)
        Spacer(Modifier.height(dims.dp(32f)))
        Text("检查连接", style = tz.type.body, color = Accent)
    }
}

@Composable
private fun EmptyPanel(isToday: Boolean) {
    val tz = LocalTz.current
    val dims = tz.dimens
    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(text = DayLogic.emptyTitle(isToday), style = tz.type.display, color = TextDim)
        Spacer(Modifier.height(dims.dp(26f)))

    }
}
