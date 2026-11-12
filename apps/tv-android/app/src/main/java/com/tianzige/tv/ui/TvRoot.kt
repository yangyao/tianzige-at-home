package com.tianzige.tv.ui

import android.view.KeyEvent as AndroidKeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalDensity
import com.tianzige.tv.ui.theme.BgBase
import com.tianzige.tv.ui.theme.LocalTz
import com.tianzige.tv.vm.HomeUiState
import com.tianzige.tv.vm.HomeViewModel

/**
 * 整个 App 的根节点，也是唯一的按键入口。
 *
 * 键位模型（docs/04-电视端UI.md §2）：
 *   ← →  换日期（跨周自动翻）
 *   ↑ ↓  换科目 / 换图 / 全屏时滚图
 *   OK   看大图
 *   返回 全屏 → 主屏；主屏 → 退出确认
 *   菜单 设置
 *
 * 除了日期条上那一个真实焦点，没有任何别的可聚焦元素；
 * 方向键在这里被消费掉，所以焦点既不会乱跑，也不会有「按住连跳的惯性」。
 */
@Composable
fun TvRoot(state: HomeUiState, vm: HomeViewModel, onExit: () -> Unit) {
    val tz = LocalTz.current
    val dims = tz.dimens
    val rootFocus = remember { FocusRequester() }
    val viewerScroll = rememberScrollState()
    val scrollStep = with(LocalDensity.current) { dims.dp(260f).toPx() }

    BackHandler { vm.onBack() }

    LaunchedEffect(Unit) {
        runCatching { rootFocus.requestFocus() }
    }
    LaunchedEffect(state.fullscreen, state.fullscreenUrl) {
        if (state.fullscreen) viewerScroll.scrollTo(0)
    }
    LaunchedEffect(state.exitRequested) {
        if (state.exitRequested) onExit()
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BgBase)
            .focusRequester(rootFocus)
            .focusable()
            .onPreviewKeyEvent { event ->
                event.type == KeyEventType.KeyDown &&
                    routeKey(event.nativeKeyEvent.keyCode, state, vm, viewerScroll, scrollStep)
            },
    ) {
        HomeScreen(state = state)
        if (state.fullscreen) {
            FullscreenViewer(url = state.fullscreenUrl, scroll = viewerScroll)
        }
        if (state.showSettings) {
            SettingsScreen(state = state)
        }
        if (state.exitConfirm) {
            ExitConfirmDialog(choice = state.exitChoice)
        }
    }
}

private const val OK_CENTER = AndroidKeyEvent.KEYCODE_DPAD_CENTER
private const val OK_ENTER = AndroidKeyEvent.KEYCODE_ENTER
private const val OK_NUMPAD = AndroidKeyEvent.KEYCODE_NUMPAD_ENTER

private fun routeKey(
    code: Int,
    state: HomeUiState,
    vm: HomeViewModel,
    scroll: ScrollState,
    step: Float,
): Boolean {
    // 设置屏是模态：所有键都归它，避免在设置时把背后的日期改掉
    if (state.showSettings) return settingsKeys(code, vm)

    if (state.exitConfirm) {
        return when (code) {
            AndroidKeyEvent.KEYCODE_DPAD_LEFT -> {
                vm.moveExitChoice(-1); true
            }
            AndroidKeyEvent.KEYCODE_DPAD_RIGHT -> {
                vm.moveExitChoice(1); true
            }
            OK_CENTER, OK_ENTER, OK_NUMPAD -> {
                vm.confirmExit(); true
            }
            else -> false
        }
    }

    if (state.fullscreen) {
        return when (code) {
            AndroidKeyEvent.KEYCODE_DPAD_UP -> {
                scroll.dispatchRawDelta(-step); true
            }
            AndroidKeyEvent.KEYCODE_DPAD_DOWN -> {
                scroll.dispatchRawDelta(step); true
            }
            // 全屏里 OK / ← → 不做别的事，防止误触把图关掉
            OK_CENTER, OK_ENTER, OK_NUMPAD -> true
            else -> false
        }
    }

    return when (code) {
        AndroidKeyEvent.KEYCODE_DPAD_LEFT -> {
            vm.moveDay(-1); true
        }
        AndroidKeyEvent.KEYCODE_DPAD_RIGHT -> {
            vm.moveDay(1); true
        }
        AndroidKeyEvent.KEYCODE_DPAD_UP -> {
            vm.stepItem(-1); true
        }
        AndroidKeyEvent.KEYCODE_DPAD_DOWN -> {
            vm.stepItem(1); true
        }
        OK_CENTER, OK_ENTER, OK_NUMPAD -> {
            if (state.day == null && state.fatalError != null) vm.openSettings() else vm.openFullscreen()
            true
        }
        AndroidKeyEvent.KEYCODE_MENU -> {
            vm.openSettings(); true
        }
        else -> false
    }
}

private fun settingsKeys(code: Int, vm: HomeViewModel): Boolean = when (code) {
    AndroidKeyEvent.KEYCODE_DPAD_LEFT -> {
        vm.settingsMove(dRow = 0, dCol = -1); true
    }
    AndroidKeyEvent.KEYCODE_DPAD_RIGHT -> {
        vm.settingsMove(dRow = 0, dCol = 1); true
    }
    AndroidKeyEvent.KEYCODE_DPAD_UP -> {
        vm.settingsMove(dRow = -1, dCol = 0); true
    }
    AndroidKeyEvent.KEYCODE_DPAD_DOWN -> {
        vm.settingsMove(dRow = 1, dCol = 0); true
    }
    OK_CENTER, OK_ENTER, OK_NUMPAD -> {
        vm.settingsActivate(); true
    }
    AndroidKeyEvent.KEYCODE_MENU -> {
        vm.closeSettings(); true
    }
    else -> false
}
