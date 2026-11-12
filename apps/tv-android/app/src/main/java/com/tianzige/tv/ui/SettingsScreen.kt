package com.tianzige.tv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.material3.Text
import com.tianzige.tv.domain.SettingsPad
import com.tianzige.tv.ui.components.TvFocusable
import com.tianzige.tv.ui.theme.BgBase
import com.tianzige.tv.ui.theme.BgRaised
import com.tianzige.tv.ui.theme.BgSurface
import com.tianzige.tv.ui.theme.ErrorRed
import com.tianzige.tv.ui.theme.Line
import com.tianzige.tv.ui.theme.LocalTz
import com.tianzige.tv.ui.theme.OkGreen
import com.tianzige.tv.ui.theme.TextDim
import com.tianzige.tv.ui.theme.TextPrimary
import com.tianzige.tv.ui.theme.TextSecondary
import com.tianzige.tv.ui.theme.Warn
import com.tianzige.tv.vm.HomeUiState

/**
 * 设置屏。遥控器没有键盘，所以只有一个 5×3 的网格：
 * 上面 4 行是 0-9 和 . 和退格，最后一行是 保存 / 测试连接 / 清除。
 * 方向键在网格里走，OK 等于按一下这个键。
 */
@Composable
fun SettingsScreen(state: HomeUiState) {
    val tz = LocalTz.current
    val dims = tz.dimens

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BgBase)
            .padding(horizontal = dims.dp(120f), vertical = dims.dp(56f)),
    ) {
        Text("服务端地址", style = tz.type.h1, color = TextPrimary)
        Spacer(Modifier.height(dims.dp(10f)))
        Text(
            text = "电视和 NAS 要连同一个 WiFi。默认 http://nas.local:8080，也可以直接输 NAS 的 IP 和端口。",
            style = tz.type.caption,
            color = TextSecondary,
        )
        Spacer(Modifier.height(dims.dp(28f)))
        AddressBox(state.settingsDraft)
        Spacer(Modifier.height(dims.dp(28f)))
        PadGrid(state)
        Spacer(Modifier.height(dims.dp(18f)))
        Notice(state)
        Spacer(Modifier.weight(1f))
        Text(
            text = "方向键移动 · OK 输入 · 菜单 返回主屏",
            style = tz.type.caption,
            color = TextDim,
        )
    }
}

@Composable
private fun AddressBox(draft: String) {
    val tz = LocalTz.current
    val dims = tz.dimens
    val shape = RoundedCornerShape(dims.dp(12f))
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(dims.dp(96f))
            .clip(shape)
            .background(BgRaised, shape)
            .border(dims.dp(1f), Line, shape)
            .padding(horizontal = dims.dp(24f)),
        contentAlignment = Alignment.CenterStart,
    ) {
        Text(
            text = draft.ifBlank { "点下面的数字键输入地址" },
            style = tz.type.body,
            color = if (draft.isBlank()) TextDim else TextPrimary,
            fontFamily = FontFamily.Monospace,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun PadGrid(state: HomeUiState) {
    val dims = LocalTz.current.dimens
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(dims.dp(16f)),
    ) {
        SettingsPad.keyRows.forEachIndexed { row, keys ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(dims.dp(88f)),
                horizontalArrangement = Arrangement.spacedBy(dims.dp(16f)),
            ) {
                keys.forEachIndexed { col, key ->
                    PadCell(
                        label = key,
                        focused = state.settingsRow == row && state.settingsCol == col,
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight(),
                        muted = key == SettingsPad.BACKSPACE,
                    )
                }
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(dims.dp(76f)),
            horizontalArrangement = Arrangement.spacedBy(dims.dp(16f)),
        ) {
            SettingsPad.actions.forEachIndexed { col, label ->
                PadCell(
                    label = label,
                    focused = state.settingsRow == SettingsPad.ACTION_ROW && state.settingsCol == col,
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight(),
                    muted = label == "清除",
                )
            }
        }
    }
}

@Composable
private fun PadCell(
    label: String,
    focused: Boolean,
    modifier: Modifier,
    muted: Boolean,
) {
    val tz = LocalTz.current
    val dims = tz.dimens
    val isDigit = label.length == 1 || label == SettingsPad.BACKSPACE

    TvFocusable(
        focused = focused,
        modifier = modifier,
        corner = dims.dp(12f),
        background = if (muted) BgSurface else BgRaised,
    ) {
        Text(
            text = label,
            style = if (isDigit) tz.type.h2 else tz.type.body,
            color = if (muted) TextDim else TextPrimary,
            modifier = Modifier.align(Alignment.Center),
            maxLines = 1,
        )
    }
}

@Composable
private fun Notice(state: HomeUiState) {
    val tz = LocalTz.current
    val message = state.settingsMessage ?: return
    val color = when {
        state.settingsTesting -> Warn
        state.settingsNoticeOk -> OkGreen
        else -> ErrorRed
    }
    Text(text = message, style = tz.type.caption, color = color)
}
