import SwiftUI

// ---------------------------------------------------------------------------
// 色值：design/tokens.json · color.*，与 Android TV 端 Theme.kt 完全一致。
// 呈现端固定深色（它扮演的是家里那块「屏」，深底 + 粉笔黄是设计稿唯一的一套）。
// 不要在这里手调颜色，改 token 再改这一处。
// ---------------------------------------------------------------------------
enum Tz {
    static let bgBase = Color(hex: 0x14181C)      // color.bg.base
    static let bgSurface = Color(hex: 0x1D2329)   // color.bg.surface
    static let bgRaised = Color(hex: 0x262E36)    // color.bg.raised
    static let textPrimary = Color(hex: 0xF2F5F8) // color.text.primary
    static let textSecondary = Color(hex: 0xA8B2BE)
    static let textDim = Color(hex: 0x6F7B88)     // color.text.dim
    static let accent = Color(hex: 0xE9B44C)      // color.accent 粉笔黄
    static let accentInk = Color(hex: 0x1A1206)   // color.accentInk
    static let brand = Color(hex: 0x3E7A5E)       // color.brand 黑板绿
    static let flower = Color(hex: 0xD9544D)      // color.flower 小红花
    static let line = Color(hex: 0x333B44)        // color.line 的实色近似
    static let warn = Color(hex: 0xE9A23B)        // color.state.warn
    static let ok = Color(hex: 0x4CAF7D)          // color.state.ok
    static let error = Color(hex: 0xD9544D)       // color.state.error
    static let okText = Color(hex: 0x86D6AA)      // ok 调亮，深底上做文字
}

/// 设置面板这类「普通 Mac 对话框」的固定字号，不走窗口缩放。
enum Fonts {
    static let title = Font.system(size: 22, weight: .semibold)
    static let body = Font.system(size: 15)
    static let caption = Font.system(size: 13)
    static let hint = Font.system(size: 12.5)
    static let button = Font.system(size: 15, weight: .semibold)
}

// ---------------------------------------------------------------------------
// 尺寸：设计稿是 1920×1080。Mac 窗口可大可小，用窗口高度的比例换算，
// 拖小窗口时字等比缩小，保证和电视端同一套布局参数。
// ---------------------------------------------------------------------------
struct TzMetrics {
    let scale: CGFloat

    static func fit(height: CGFloat) -> TzMetrics {
        TzMetrics(scale: Swift.min(Swift.max(height / 1080, 0.5), 1.6))
    }

    func dp(_ value: CGFloat) -> CGFloat { value * scale }

    func font(_ px: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: px * scale, weight: weight)
    }

    // font.*.tv，见 tokens.json
    var display: Font { font(72, .bold) }
    var h1: Font { font(52, .bold) }
    var h2: Font { font(42, .semibold) }
    var body: Font { font(34) }
    var caption: Font { font(25) }
    var min: Font { font(22) }
    /// 作业条目：42px / 1.72（docs/04-电视端UI.md §3）
    var item: Font { font(42) }
    var itemLineSpacing: CGFloat { 30 * scale }  // 72 - 42
    /// 日期条上的日号：40px / 600
    var dateNumber: Font { font(40, .semibold) }
}

private struct TzMetricsKey: EnvironmentKey {
    static let defaultValue = TzMetrics(scale: 1)
}

extension EnvironmentValues {
    var tz: TzMetrics {
        get { self[TzMetricsKey.self] }
        set { self[TzMetricsKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
