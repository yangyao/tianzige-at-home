package com.tianzige.tv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.painter.ColorPainter
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import coil.compose.AsyncImage
import com.tianzige.tv.data.DayView
import com.tianzige.tv.domain.DayLogic
import com.tianzige.tv.ui.theme.*
import com.tianzige.tv.vm.HomeViewModel

// Photos and subjects participate in the same native spatial focus search as dates.
@Composable
fun PendingPanel(day: DayView, imageIndex: Int, baseUrl: String, vm: HomeViewModel) {
    val dims = LocalTz.current.dimens
    val rows = day.images.chunked(3)
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(dims.dp(24f))) {
        rows.forEachIndexed { rowIndex, images ->
            Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(dims.dp(24f))) {
                images.forEachIndexed { columnIndex, image ->
                    val index = rowIndex * 3 + columnIndex
                    PhotoCard(
                        url = DayLogic.absoluteUrl(baseUrl, image.url),
                        modifier = Modifier.weight(1f).fillMaxHeight(),
                        onFocus = { vm.selectImage(index) },
                        onOpen = vm::openFullscreen,
                    )
                }
            }
        }
    }
}

@Composable
fun ReadyPanel(day: DayView, baseUrl: String, vm: HomeViewModel) {
    val tz = LocalTz.current
    val dims = tz.dimens
    Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(dims.dp(40f))) {
        Column(Modifier.weight(0.52f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(dims.dp(16f))) {
            day.images.forEachIndexed { index, image ->
                PhotoCard(
                    url = DayLogic.absoluteUrl(baseUrl, image.url),
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                    onFocus = { vm.selectImage(index) },
                    onOpen = vm::openFullscreen,
                )
            }
        }
        Column(
            Modifier.weight(0.48f).fillMaxHeight().clipToBounds(),
            verticalArrangement = Arrangement.spacedBy(dims.dp(28f)),
        ) {
            day.subjects.forEach { group ->
                Column(verticalArrangement = Arrangement.spacedBy(dims.dp(12f))) {
                    Text(group.subject, style = tz.type.body, color = Accent)
                    group.items.forEach { item ->
                        Text(item.content, style = tz.type.h2, color = TextPrimary)
                    }
                }
            }
        }
    }
}

@Composable
private fun PhotoCard(url: String?, modifier: Modifier, onFocus: () -> Unit, onOpen: () -> Unit) {
    val tz = LocalTz.current
    val dims = tz.dimens
    var focused by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(dims.dp(20f))
    Box(
        modifier.onFocusChanged {
            focused = it.isFocused
            if (it.isFocused) onFocus()
        }.onKeyEvent {
            if (it.type == KeyEventType.KeyDown && it.nativeKeyEvent.keyCode in listOf(23, 66)) {
                onOpen(); true
            } else false
        }.focusable()
            .clip(shape)
            .background(BgSurface, shape)
            .border(if (focused) dims.dp(4f) else dims.dp(1f), if (focused) Accent else Line, shape),
    ) {
        if (url != null) {
            AsyncImage(
                model = url,
                contentDescription = "作业原图",
                modifier = Modifier.fillMaxSize().padding(dims.dp(5f)),
                contentScale = ContentScale.Fit,
                placeholder = ColorPainter(BgSurface),
                error = ColorPainter(BgSurface),
            )
        }
    }
}
