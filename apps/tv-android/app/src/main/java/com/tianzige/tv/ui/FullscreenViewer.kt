package com.tianzige.tv.ui

import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.painter.ColorPainter
import androidx.compose.ui.layout.ContentScale
import androidx.tv.material3.Text
import coil.compose.AsyncImage
import com.tianzige.tv.ui.theme.LocalTz
import com.tianzige.tv.ui.theme.TextDim
import com.tianzige.tv.ui.theme.TextSecondary

/**
 * 全屏看图：纯黑铺满，图片按宽度适配，↑↓ 上滚（docs/04-电视端UI.md §7）。
 * 黑板字小，全屏才是主要阅读方式，所以这里不允许出现任何按钮挡住图。
 */
@Composable
fun FullscreenViewer(url: String?, scroll: ScrollState) {
    val tz = LocalTz.current
    val dims = tz.dimens
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { appeared = true }
    val progress by animateFloatAsState(
        targetValue = if (appeared) 1f else 0f,
        animationSpec = tween(durationMillis = 200, easing = LinearOutSlowInEasing),
        label = "viewer",
    )

    Box(
        modifier = Modifier
            .fillMaxSize()
            .graphicsLayer {
                alpha = progress
                val s = 0.96f + 0.04f * progress
                scaleX = s
                scaleY = s
            }
            .background(Color.Black),
    ) {
        if (url == null) {
            Text(
                text = "没有原图",
                style = tz.type.body,
                color = TextDim,
                modifier = Modifier.align(Alignment.Center),
            )
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(scroll),
            ) {
                AsyncImage(
                    model = url,
                    contentDescription = "作业原图",
                    modifier = Modifier.fillMaxWidth(),
                    contentScale = ContentScale.FillWidth,
                    placeholder = ColorPainter(Color.Black),
                    error = ColorPainter(Color.Black),
                )
            }

            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(dims.dp(88f))
                    .background(
                        Brush.verticalGradient(
                            listOf(Color.Transparent, Color.Black.copy(alpha = 0.9f))
                        )
                    )
                    .padding(bottom = dims.dp(12f)),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "↑ ↓ 滚动图片 · 返回 关闭",
                    style = tz.type.caption,
                    color = TextSecondary,
                )
            }
        }
    }
}
