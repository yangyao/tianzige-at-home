package com.tianzige.tv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.material3.Text
import com.tianzige.tv.R
import com.tianzige.tv.ui.components.TvFocusable
import com.tianzige.tv.ui.theme.BgSurface
import com.tianzige.tv.ui.theme.LocalTz
import com.tianzige.tv.ui.theme.TextDim
import com.tianzige.tv.ui.theme.TextPrimary

/**
 * 主屏按返回时的确认框。任何方向键都不应该直接把人踢出 App 或者什么都不发生，
 * 所以用两个按钮 + ←→ 明确选一下（0 = 继续看，1 = 退出）。
 */
@Composable
fun ExitConfirmDialog(choice: Int) {
    val tz = LocalTz.current
    val dims = tz.dimens

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.74f)),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(stringResource(R.string.exit_question), style = tz.type.h1, color = TextPrimary)
            Spacer(Modifier.height(dims.dp(28f)))
            Row(horizontalArrangement = Arrangement.spacedBy(dims.dp(24f))) {
                ChoicePill(label = stringResource(R.string.keep_watching), focused = choice == 0)
                ChoicePill(label = stringResource(R.string.exit), focused = choice == 1)
            }
            Spacer(Modifier.height(dims.dp(24f)))
            Text(stringResource(R.string.exit_hint), style = tz.type.caption, color = TextDim)
        }
    }
}

@Composable
private fun ChoicePill(label: String, focused: Boolean) {
    val tz = LocalTz.current
    val dims = tz.dimens
    TvFocusable(
        focused = focused,
        modifier = Modifier
            .width(dims.dp(240f))
            .height(dims.dp(88f)),
        corner = dims.dp(999f),
        background = BgSurface,
    ) {
        Text(
            text = label,
            style = tz.type.h2,
            color = TextPrimary,
            modifier = Modifier.align(Alignment.Center),
        )
    }
}
