import SwiftUI
import UIKit

/// 设计 token 的唯一入口，色值与字号来自 `design/tokens.json`。
///
/// 深色值就是 token 原值；浅色值给同色相的可读变体（token 只定义了深色，
/// 因为电视端强制深色，而手机上要跟随系统）。新增颜色请先改 tokens.json，
/// 再在这里登记，不要在 View 里直接写 hex。
enum Theme {

    // MARK: - 颜色（token: color.*）

    /// token: color.bg.base
    static let bgBase = Color(light: 0xFAF9F6, dark: 0x14181C)
    /// token: color.bg.surface
    static let bgSurface = Color(light: 0xFFFFFF, dark: 0x1D2329)
    /// token: color.bg.raised
    static let bgRaised = Color(light: 0xE8ECF1, dark: 0x262E36)
    /// token: color.text.primary
    static let textPrimary = Color(light: 0x14181C, dark: 0xF2F5F8)
    /// token: color.text.secondary
    static let textSecondary = Color(light: 0x4C5866, dark: 0xA8B2BE)
    /// token: color.text.dim
    static let textDim = Color(light: 0x7C8896, dark: 0x6F7B88)
    /// token: color.accent
    static let accent = Color(hex: 0xE9B44C)
    /// token: color.accentInk
    static let accentInk = Color(hex: 0x1A1206)
    /// token: color.brand
    static let brand = Color(hex: 0x3E7A5E)
    static let primaryAction = Color(light: 0x326B50, dark: 0x3E7A5E)
    /// token: color.flower
    static let flower = Color(hex: 0xD9544D)
    /// token: color.state.ok
    static let stateOK = Color(hex: 0x4CAF7D)
    /// token: color.state.warn
    static let stateWarn = Color(hex: 0xE9A23B)
    /// token: color.state.error
    static let stateError = Color(hex: 0xD9544D)

    /// token: color.line —— 深色 rgba(255,255,255,.09)，浅色取同亮度的黑
    static let line = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.09)
                : UIColor(hex: 0x14181C, alpha: 0.10)
        }
    )

    // MARK: - 字号（token: font.ui.*）

    enum Fonts {
        /// token: font.ui.title（22 / 700）
        static let title = SwiftUI.Font.system(size: 22, weight: .bold)
        /// token: font.ui.body（15 / 400）
        static let body = SwiftUI.Font.system(size: 15, weight: .regular)
        /// token: font.ui.body，加重
        static let bodySemibold = SwiftUI.Font.system(size: 15, weight: .semibold)
        /// 主按钮：拿在手里要一眼看到，比 body 大一档、比 title 小一档
        static let button = SwiftUI.Font.system(size: 17, weight: .semibold)
        /// 上传区主文案：略大于 body，让「把作业照片放进来」先被看到
        static let sectionTitle = SwiftUI.Font.system(size: 26, weight: .bold)
        /// token: font.ui.caption（13 / 400）
        static let caption = SwiftUI.Font.system(size: 13, weight: .regular)
        /// token: font.ui.min（12 / 400）
        static let min = SwiftUI.Font.system(size: 12, weight: .regular)
    }

    // MARK: - 间距（token: space.*）

    enum Space {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 24
        static let s6: CGFloat = 32
        static let s7: CGFloat = 48
        static let s8: CGFloat = 64
    }

    // MARK: - 圆角（token: radius.*）

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 20
        static let full: CGFloat = 999
    }
}

extension Color {
    /// tokens.json 里的固定色（不随深浅色变化）。
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// 自适应色：浅色与深色各给一个 hex。
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}
