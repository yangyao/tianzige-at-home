import SwiftUI

/// 菜单栏图标：一个「田」字——外框 + 横竖中线。
/// 用 Canvas 手画，不依赖 SF Symbol；颜色用 .primary，跟随菜单栏深浅色自动反色。
struct MenuBarIcon: View {
    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 2
            let rect = CGRect(
                x: inset,
                y: inset,
                width: size.width - inset * 2,
                height: size.height - inset * 2
            )
            let lineWidth: CGFloat = 1.4

            let frame = Path(roundedRect: rect, cornerRadius: 2.5)
            context.stroke(frame, with: .color(Color.primary), lineWidth: lineWidth)

            var horizontal = Path()
            horizontal.move(to: CGPoint(x: rect.minX, y: rect.midY))
            horizontal.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            context.stroke(horizontal, with: .color(Color.primary), lineWidth: lineWidth)

            var vertical = Path()
            vertical.move(to: CGPoint(x: rect.midX, y: rect.minY))
            vertical.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            context.stroke(vertical, with: .color(Color.primary), lineWidth: lineWidth)
        }
        .frame(width: 17, height: 17)
        .accessibilityLabel(L10n.string("app.name"))
    }
}

/// 上传区里的 2×2 小格子图形（对应 tokens 里的田字格意象）。
struct GridGlyph: View {
    var side: CGFloat = 34
    var color: Color = Theme.accent

    var body: some View {
        Canvas { context, size in
            let gap = size.width * 0.14
            let cell = (size.width - gap) / 2
            for row in 0..<2 {
                for column in 0..<2 {
                    let origin = CGPoint(
                        x: CGFloat(column) * (cell + gap),
                        y: CGFloat(row) * (cell + gap)
                    )
                    let rect = CGRect(origin: origin, size: CGSize(width: cell, height: cell))
                        .insetBy(dx: cell * 0.08, dy: cell * 0.08)
                    let path = Path(roundedRect: rect, cornerRadius: cell * 0.16)
                    context.stroke(path, with: .color(color), lineWidth: max(1.1, cell * 0.11))
                }
            }
        }
        .frame(width: side, height: side)
    }
}
