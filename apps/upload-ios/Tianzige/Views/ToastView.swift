import SwiftUI

/// 6 秒自动消失的轻提示。点一下也能立刻收掉。
struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: Theme.Space.s2) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)

            Text(message.text)
                .font(Theme.Fonts.body)
                .foregroundColor(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.s4)
        .padding(.vertical, Theme.Space.s3)
        .background(Theme.bgRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }

    private var indicatorColor: Color {
        switch message.kind {
        case .success: return Theme.stateOK
        case .info: return Theme.accent
        case .error: return Theme.stateError
        }
    }
}
