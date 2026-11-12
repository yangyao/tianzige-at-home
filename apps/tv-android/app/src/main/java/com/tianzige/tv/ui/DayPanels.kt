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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.painter.ColorPainter
import androidx.compose.ui.layout.ContentScale
import androidx.tv.material3.Text
import coil.compose.AsyncImage
import com.tianzige.tv.data.DayView
import com.tianzige.tv.domain.DayLogic
import com.tianzige.tv.ui.theme.Accent
import com.tianzige.tv.ui.theme.BgOverlay
import com.tianzige.tv.ui.theme.BgSurface
import com.tianzige.tv.ui.theme.Line
import com.tianzige.tv.ui.theme.LocalTz
import com.tianzige.tv.ui.theme.TextDim
import com.tianzige.tv.ui.theme.TextPrimary
import com.tianzige.tv.ui.theme.Warn

/**
 * pending：有图但没识别完。只显示原图 + 「正在识别」。
 * 绝不能显示成「今天没作业」（协议 §5.2）。
 */
@Composable
fun PendingPanel(day: DayView, imageIndex: Int, baseUrl: String) {
    val tz = LocalTz.current
    val dims = tz.dimens
    val total = day.images.size
    val current = DayLogic.clampIndex(imageIndex, total)

    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dims.dp(14f)),
        ) {
            Box(
                Modifier
                    .size(dims.dp(12f))
                    .clip(CircleShape)
                    .background(Warn)
            )
            Text("正在识别，先看图 · 图是准的", style = tz.type.h2, color = Warn, maxLines = 1)
        }
        Spacer(Modifier.height(dims.dp(24f)))

        // 一屏最多 6 张（2 行 × 3 列），再多也不是孩子该一屏看的量
        val rows = day.images.take(6).chunked(3)
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(dims.dp(16f)),
        ) {
            rows.forEachIndexed { rowIndex, rowImages ->
                Row(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(dims.dp(16f)),
                ) {
                    rowImages.forEachIndexed { colIndex, image ->
                        val index = rowIndex * 3 + colIndex
                        PhotoCard(
                            url = DayLogic.absoluteUrl(baseUrl, image.url),
                            tag = null,
                            highlighted = index == current,
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxHeight(),
                        )
                    }
                    repeat(3 - rowImages.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }

        Spacer(Modifier.height(dims.dp(12f)))
        Text(
            text = if (total > 1) "第 ${current + 1} / $total 张 · OK 看大图" else "OK 看大图",
            style = tz.type.caption,
            color = TextDim,
        )
    }
}

/**
 * ready：左图右文。左侧 58%，右侧 42%（tokens.json layout.tv）。
 * 文字区永远带一句「识别结果，仅供参考 · 以原图为准」。
 */
@Composable
fun ReadyPanel(day: DayView, subjectIndex: Int, baseUrl: String) {
    val tz = LocalTz.current
    val dims = tz.dimens
    val subjects = day.subjects
    val index = DayLogic.clampIndex(subjectIndex, subjects.size)
    val subject = subjects.getOrNull(index)
    val imageUrl = DayLogic.resolveImageUrl(subject?.imageUrl, day.images.firstOrNull()?.url)

    Row(
        modifier = Modifier.fillMaxSize(),
        horizontalArrangement = Arrangement.spacedBy(dims.dp(44f)),
    ) {
        PhotoCard(
            url = DayLogic.absoluteUrl(baseUrl, imageUrl),
            tag = subject?.let { "${it.subject} ${index + 1} / ${subjects.size}" },
            highlighted = false,
            modifier = Modifier
                .weight(0.58f)
                .fillMaxHeight(),
        )
        Column(
            modifier = Modifier
                .weight(0.42f)
                .fillMaxHeight(),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(dims.dp(16f)),
            ) {
                Text(
                    text = subject?.subject.orEmpty(),
                    style = tz.type.h1,
                    color = TextPrimary,
                    maxLines = 1,
                )
                if (subjects.size > 1) {
                    Text(
                        text = "第 ${index + 1} 项 / 共 ${subjects.size} 项",
                        style = tz.type.caption,
                        color = TextDim,
                        maxLines = 1,
                    )
                }
            }
            Spacer(Modifier.height(dims.dp(18f)))
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(dims.dp(2f))
                    .background(Line)
            )
            Spacer(Modifier.height(dims.dp(26f)))

            // 电视上不允许滚动（DESIGN.md §10），条目多了就裁掉，原图永远是完整可看的
            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .clipToBounds(),
                verticalArrangement = Arrangement.spacedBy(dims.dp(26f)),
            ) {
                subject?.items?.forEachIndexed { i, item ->
                    Row {
                        Text(
                            text = "${i + 1}",
                            style = tz.type.item,
                            color = Accent,
                            modifier = Modifier.width(dims.dp(56f)),
                        )
                        Text(text = item.content, style = tz.type.item, color = TextPrimary)
                    }
                }
            }

            Text(
                text = "识别结果，仅供参考 · 以原图为准",
                style = tz.type.caption,
                color = TextDim,
                modifier = Modifier.padding(top = dims.dp(16f)),
            )
        }
    }
}

@Composable
private fun PhotoCard(
    url: String?,
    tag: String?,
    highlighted: Boolean,
    modifier: Modifier,
) {
    val tz = LocalTz.current
    val dims = tz.dimens
    val shape = RoundedCornerShape(dims.dp(20f))
    val borderColor = if (highlighted) Accent else Line
    val borderWidth = if (highlighted) dims.dp(3f) else dims.dp(1f)

    Box(
        modifier = modifier
            .clip(shape)
            .background(BgSurface, shape)
            .border(borderWidth, borderColor, shape),
    ) {
        if (url.isNullOrBlank()) {
            Text(
                text = "没有原图",
                style = tz.type.caption,
                color = TextDim,
                modifier = Modifier.align(Alignment.Center),
            )
        } else {
            AsyncImage(
                model = url,
                contentDescription = "作业原图",
                modifier = Modifier
                    .fillMaxSize()
                    .padding(dims.dp(2f)),
                contentScale = ContentScale.Fit,
                placeholder = ColorPainter(BgSurface),
                error = ColorPainter(BgSurface),
            )
        }

        if (tag != null) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(dims.dp(18f))
                    .clip(RoundedCornerShape(dims.dp(8f)))
                    .background(BgOverlay)
                    .padding(horizontal = dims.dp(16f), vertical = dims.dp(8f)),
            ) {
                Text(text = tag, style = tz.type.min, color = TextPrimary)
            }
        }
    }
}
