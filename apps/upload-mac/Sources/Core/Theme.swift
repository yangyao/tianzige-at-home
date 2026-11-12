import AppKit
import SwiftUI

/// 色彩、字号、间距、圆角。
/// 数值取自 `design/tokens.json`，注释里标了对应的 token 名；不要在这里随手发明颜色。
/// tokens.json 只给了深色一套，浅色按同样的对比关系取相近的浅色值。
enum Theme {

    // MARK: - 固定色（深浅色通用，token 本身就是给深底设计的强调色）

    /// color.accent —— 粉笔黄。主按钮、焦点、强调数字
    static let accent = Color(hex: 0xE9B44C)
    /// color.accentInk —— accent 底上的文字
    static let accentInk = Color(hex: 0x1A1206)
    /// color.brand —— 黑板绿
    static let brand = Color(hex: 0x3E7A5E)
    /// color.flower —— 小红花红
    static let flower = Color(hex: 0xD9544D)
    /// color.state.ok
    static let ok = Color(hex: 0x4CAF7D)
    /// color.state.warn
    static let warn = Color(hex: 0xE9A23B)
    /// color.state.error
    static let error = Color(hex: 0xD9544D)

    // MARK: - 跟随系统深浅色的语义色

    /// color.bg.base
    static let bgBase = adaptive(light: 0xF4F5F7, dark: 0x14181C)
    /// color.bg.surface
    static let bgSurface = adaptive(light: 0xFFFFFF, dark: 0x1D2329)
    /// color.bg.raised
    static let bgRaised = adaptive(light: 0xEDF0F5, dark: 0x262E36)
    /// color.text.primary
    static let textPrimary = adaptive(light: 0x171A20, dark: 0xF2F5F8)
    /// color.text.secondary
    static let textSecondary = adaptive(light: 0x646F7E, dark: 0xA8B2BE)
    /// color.text.dim
    static let textDim = adaptive(light: 0x95A0AE, dark: 0x6F7B88)
    /// color.line —— 深色是 rgba(255,255,255,.09)，这里取了落在 surface 上的近似实色
    static let line = adaptive(light: 0xDDE2EA, dark: 0x333B44)

    /// 成功提示条（由 color.state.ok 调浅 / 调深）
    static let okSurface = adaptive(light: 0xE8F6EE, dark: 0x1C3328)
    static let okText = adaptive(light: 0x0F7A4C, dark: 0x86D6AA)
    /// 黄条（由 color.state.warn 调浅 / 调深）
    static let warnSurface = adaptive(light: 0xFDF3E3, dark: 0x392D1B)
    static let warnText = adaptive(light: 0x8A5A12, dark: 0xEBC37D)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

/// tokens.json → space.*
enum Space {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
}

/// tokens.json → radius.*
enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 20
}

/// tokens.json → font.ui.*（title 22 / body 15 / caption 13 / min 12）
enum Fonts {
    static let title = Font.system(size: 22, weight: .semibold)
    static let body = Font.system(size: 15)
    static let caption = Font.system(size: 13)
    static let hint = Font.system(size: 12.5)
    static let button = Font.system(size: 15, weight: .semibold)
    static let dropTitle = Font.system(size: 16, weight: .semibold)
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }
}
