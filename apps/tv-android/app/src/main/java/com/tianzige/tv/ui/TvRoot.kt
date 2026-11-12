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

/** 首页使用原生空间焦点；这里只处理设置、退出和大图的模态按键。 */
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
        HomeScreen(state = state, vm = vm)
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
        // Home navigation follows visible focusable dates, photos and subjects.
        OK_CENTER, OK_ENTER, OK_NUMPAD -> {
            if (state.day == null && state.fatalError != null) { vm.openSettings(); true } else false
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
