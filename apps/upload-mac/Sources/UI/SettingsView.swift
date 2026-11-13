import AppKit
import SwiftUI

/// 设置窗口：只有一件事——NAS 地址 + 测一下通不通。
struct SettingsView: View {
    @EnvironmentObject private var store: UploadStore
    @AppStorage(DefaultsKey.nasBaseURL) private var address = APIClient.defaultBase

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(L10n.string("settings.nasAddress"))
                .font(Fonts.caption)
                .foregroundStyle(Theme.textSecondary)

            TextField(APIClient.defaultBase, text: $address)
                .textFieldStyle(.plain)
                .font(Fonts.body)
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Theme.bgSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
                .onSubmit { store.refreshHealth(force: true) }

            HStack(spacing: Space.s3) {
                Button {
                    store.refreshHealth(force: true)
                } label: {
                    Text(store.isCheckingHealth
                         ? L10n.string("settings.testing")
                         : L10n.string("settings.testConnection"))
                        .font(Fonts.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(Theme.bgRaised)
                        )
                }
                .buttonStyle(.plain)
                .disabled(store.isCheckingHealth)

                statusLabel
                    .font(Fonts.caption)
            }

            Text(L10n.string("settings.presetHint"))
                .font(Fonts.hint)
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(L10n.string("settings.done")) {
                    WindowManager.shared.closeSettingsWindow()
                }
                .buttonStyle(.plain)
                .font(Fonts.body)
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(Space.s5)
        .frame(width: 400, height: 250, alignment: .topLeading)
        .background(Theme.bgBase)
        .onAppear { store.refreshHealth() }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch store.health {
        case .unknown:
            Text(L10n.string("settings.status.unknown"))
                .foregroundStyle(Theme.textDim)
        case .checking:
            Text(L10n.string("settings.testing"))
                .foregroundStyle(Theme.textSecondary)
        case .ok:
            Text(L10n.string("settings.status.ok"))
                .foregroundStyle(Theme.ok)
        case .down:
            Text(L10n.string("settings.status.down"))
                .foregroundStyle(Theme.error)
        }
    }
}
