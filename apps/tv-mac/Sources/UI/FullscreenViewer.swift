import SwiftUI

/// 全屏看图：纯黑铺满，图片按窗口宽度适配，上下滚动（docs/04-电视端UI.md §7）。
/// 这里不允许出现任何挡图的东西，只有右上角一个 ×，Esc / 点 × 关闭。
struct FullscreenViewer: View {
    let url: String?
    let onClose: () -> Void
    @Environment(\.tz) private var tz

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let url, let imageUrl = URL(string: url) {
                ScrollView(.vertical, showsIndicators: true) {
                    AsyncImage(url: imageUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, tz.dp(40))
                                .padding(.vertical, tz.dp(40))
                        default:
                            Color.black
                                .frame(maxWidth: .infinity, minHeight: 400)
                        }
                    }
                }
            } else {
                Text(L10n.string("no_photo"))
                    .font(tz.body)
                    .foregroundStyle(Tz.textDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: tz.dp(30), weight: .medium))
                    .foregroundStyle(Tz.textSecondary)
                    .padding(tz.dp(24))
            }
            .buttonStyle(.plain)
            .help(L10n.string("close"))
            .padding(tz.dp(16))
        }
        // Esc 关全屏：隐藏按钮挂系统快捷键，比焦点管理可靠。
        .overlay {
            Button("") { onClose() }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
