package com.tianzige.tv.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme

// ---------------------------------------------------------------------------
// 色值：design/tokens.json · color.*
// 不要在这里手调颜色，改 token 再改这一处。
// ---------------------------------------------------------------------------
val BgBase = Color(0xFF14181C)        // color.bg.base
val BgSurface = Color(0xFF1D2329)     // color.bg.surface
val BgRaised = Color(0xFF262E36)      // color.bg.raised
val BgOverlay = Color(0xDB000000)     // color.bg.overlay  rgba(0,0,0,.86)
val TextPrimary = Color(0xFFF2F5F8)   // color.text.primary
val TextSecondary = Color(0xFFA8B2BE) // color.text.secondary
val TextDim = Color(0xFF6F7B88)       // color.text.dim
val Accent = Color(0xFFE9B44C)        // color.accent
val AccentInk = Color(0xFF1A1206)     // color.accentInk
val Brand = Color(0xFF3E7A5E)         // color.brand
val Flower = Color(0xFFD9544D)        // color.flower
val OkGreen = Color(0xFF4CAF7D)       // color.state.ok
val Warn = Color(0xFFE9A23B)          // color.state.warn
val ErrorRed = Color(0xFFD9544D)      // color.state.error
val Line = Color(0x17FFFFFF)          // color.line  rgba(255,255,255,.09)

// 常量别名，避免 typo；语义见 DESIGN.md §2
val FocusBorder = Accent              // focus.borderColor
const val FOCUS_SCALE = 1.03f         // focus.scale
const val FOCUS_GLOW_ALPHA = 0.16f    // focus.glow 里的 .16
const val FOCUS_MS = 120              // focus.durationMs / motion.focusMs

/**
 * 设计稿是 1920×1080 像素。电视盒子有 1080p、720p、4K 各种密度，
 * 用屏幕高度的比例换算，保证「三米外能看清」的物理尺寸不随分辨率漂移。
 */
@Immutable
class TzDimens(val scale: Float, private val density: Density) {

    /** 设计稿 px → 屏幕 dp */
    fun dp(value: Float): Dp = with(density) { (value * scale).toDp() }

    /** 设计稿 px → sp（toSp 已经处理了 fontScale） */
    fun sp(value: Float): TextUnit = with(density) { (value * scale).toSp() }

    fun px(value: Float): Float = value * scale
}

/** font.*.tv，见 tokens.json。 */
@Immutable
class TzType(dimens: TzDimens) {
    val display = TextStyle(fontSize = dimens.sp(72f), fontWeight = FontWeight.Bold, lineHeight = dimens.sp(88f))
    val h1 = TextStyle(fontSize = dimens.sp(52f), fontWeight = FontWeight.Bold, lineHeight = dimens.sp(64f))
    val h2 = TextStyle(fontSize = dimens.sp(42f), fontWeight = FontWeight.SemiBold, lineHeight = dimens.sp(52f))
    val body = TextStyle(fontSize = dimens.sp(34f), fontWeight = FontWeight.Normal, lineHeight = dimens.sp(48f))
    val caption = TextStyle(fontSize = dimens.sp(25f), fontWeight = FontWeight.Normal, lineHeight = dimens.sp(34f))
    val min = TextStyle(fontSize = dimens.sp(22f), fontWeight = FontWeight.Normal, lineHeight = dimens.sp(30f))

    /** 作业条目：42px / 1.72（docs/04-电视端UI.md §3） */
    val item = TextStyle(fontSize = dimens.sp(42f), fontWeight = FontWeight.Normal, lineHeight = dimens.sp(72f))

    /** 日期条上的日号：40px / 600 */
    val dateNumber = TextStyle(fontSize = dimens.sp(40f), fontWeight = FontWeight.SemiBold, lineHeight = dimens.sp(44f))
}

@Immutable
class Tz(val dimens: TzDimens, val type: TzType)

val LocalTz = staticCompositionLocalOf<Tz> { error("TzTheme 没有包在外层") }

private val TzColorScheme = darkColorScheme(
    primary = Accent,
    onPrimary = AccentInk,
    secondary = Flower,
    onSecondary = Color.White,
    background = BgBase,
    onBackground = TextPrimary,
    surface = BgSurface,
    onSurface = TextPrimary,
    surfaceVariant = BgRaised,
    onSurfaceVariant = TextSecondary,
    error = ErrorRed,
    onError = Color.White,
)

@Composable
fun TzTheme(content: @Composable () -> Unit) {
    val density = LocalDensity.current
    val configuration = LocalConfiguration.current
    val scale = remember(configuration.screenWidthDp, configuration.screenHeightDp, density.density) {
        val heightPx = configuration.screenHeightDp * density.density
        (heightPx / 1080f).coerceIn(0.55f, 1.8f)
    }
    val tz = remember(scale, density) {
        val dimens = TzDimens(scale, density)
        Tz(dimens = dimens, type = TzType(dimens))
    }
    CompositionLocalProvider(LocalTz provides tz) {
        MaterialTheme(colorScheme = TzColorScheme) {
            content()
        }
    }
}
