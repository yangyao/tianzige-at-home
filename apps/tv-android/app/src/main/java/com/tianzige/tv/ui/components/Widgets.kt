package com.tianzige.tv.ui.components

import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.lerp
import androidx.tv.material3.Text
import com.tianzige.tv.ui.theme.Accent
import com.tianzige.tv.ui.theme.BgRaised
import com.tianzige.tv.ui.theme.FOCUS_GLOW_ALPHA
import com.tianzige.tv.ui.theme.FOCUS_MS
import com.tianzige.tv.ui.theme.FOCUS_SCALE
import com.tianzige.tv.ui.theme.Line
import com.tianzige.tv.ui.theme.LocalTz
import com.tianzige.tv.ui.theme.TextDim
import com.tianzige.tv.ui.theme.TextSecondary

/**
 * 全局唯一的焦点视觉（DESIGN.md §6）：
 * 4px accent 边框 + 8px 外发光 + scale(1.03)，120ms ease-out。
 *
 * 这里只负责「看起来选中了」，focused 由调用方决定：
 * 日期条用真实 Compose 焦点，设置屏用自管的行列坐标。
 */
@Composable
fun TvFocusable(
    focused: Boolean,
    modifier: Modifier = Modifier,
    corner: Dp? = null,
    background: Color = BgRaised,
    idleBorder: Color = Line,
    content: @Composable BoxScope.() -> Unit,
) {
    val dims = LocalTz.current.dimens
    val radius = corner ?: dims.dp(12f)
    val shape: Shape = RoundedCornerShape(radius)
    val progress by animateFloatAsState(
        targetValue = if (focused) 1f else 0f,
        animationSpec = tween(durationMillis = FOCUS_MS, easing = LinearOutSlowInEasing),
        label = "focus",
    )

    Box(
        modifier = modifier
            .graphicsLayer {
                scaleX = 1f + (FOCUS_SCALE - 1f) * progress
                scaleY = 1f + (FOCUS_SCALE - 1f) * progress
            }
            .drawBehind {
                if (progress > 0.01f) {
                    val glow = dims.dp(8f).toPx() * progress
                    val r = radius.toPx()
                    drawRoundRect(
                        color = Accent.copy(alpha = FOCUS_GLOW_ALPHA * progress),
                        topLeft = Offset(-glow, -glow),
                        size = Size(size.width + glow * 2, size.height + glow * 2),
                        cornerRadius = CornerRadius(r + glow, r + glow),
                    )
                }
            }
            .clip(shape)
            .background(background, shape)
            .border(
                width = lerp(dims.dp(1f), dims.dp(4f), progress),
                color = lerp(idleBorder, Accent, progress),
                shape = shape,
            ),
        content = content,
    )
}

/** 胶囊角标：「3 天前」、「上次更新 17:32」。 */
@Composable
fun Chip(
    text: String,
    modifier: Modifier = Modifier,
    color: Color = TextSecondary,
    background: Color = BgRaised,
) {
    val dims = LocalTz.current.dimens
    val shape = RoundedCornerShape(dims.dp(999f))
    Box(
        modifier = modifier
            .clip(shape)
            .background(background, shape)
            .border(dims.dp(1f), Line, shape)
            .padding(horizontal = dims.dp(18f), vertical = dims.dp(8f)),
    ) {
        Text(text = text, style = LocalTz.current.type.min, color = color)
    }
}

/** 底栏键位提示：一个方框 + 一句说明。 */
@Composable
fun KeyHint(keys: List<String>, label: String) {
    val tz = LocalTz.current
    val dims = tz.dimens
    Row(verticalAlignment = Alignment.CenterVertically) {
        keys.forEach { key ->
            val shape = RoundedCornerShape(dims.dp(8f))
            Box(
                modifier = Modifier
                    .clip(shape)
                    .background(BgRaised, shape)
                    .border(dims.dp(1f), Line, shape)
                    .padding(horizontal = dims.dp(12f), vertical = dims.dp(5f)),
                contentAlignment = Alignment.Center,
            ) {
                Text(text = key, style = tz.type.min, color = TextSecondary)
            }
            Spacer(Modifier.width(dims.dp(10f)))
        }
        Text(text = label, style = tz.type.caption, color = TextDim)
    }
}
