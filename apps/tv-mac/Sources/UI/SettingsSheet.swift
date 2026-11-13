import SwiftUI

/// 设置面板：Mac 上有键盘，直接一个输入框，不需要电视端那套 5×3 数字键盘。
/// 「保存」会清缓存回到今天；「测试连接」只探一下 /api/health，不动当前画面。
struct SettingsSheet: View {
    @ObservedObject var vm: HomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var notice: SettingsNotice?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("server_address"))
                .font(Fonts.title)
                .foregroundStyle(Tz.textPrimary)
            Text(L10n.string("server_hint"))
                .font(Fonts.hint)
                .foregroundStyle(Tz.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("http://nas.local:8080", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(Fonts.body)

            noticeLine

            HStack {
                Spacer()
                Button(L10n.string("clear")) {
                    draft = ""
                    notice = nil
                }
                Button(L10n.string("test_connection")) {
                    vm.testConnection(draft: draft)
                }
                Button(L10n.string("save")) {
                    vm.saveSettings(draft: draft)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Tz.bgSurface)
        .onAppear {
            draft = vm.state.serverUrl
            notice = vm.state.settingsNotice
        }
        .onChange(of: vm.state.settingsNotice) { newValue in
            notice = newValue
        }
        .onChange(of: vm.state.showSettings) { showing in
            if !showing { dismiss() }
        }
    }

    @ViewBuilder
    private var noticeLine: some View {
        let text = notice.map(Texts.noticeText)
        Group {
            if let text, let notice {
                switch notice {
                case .connected:
                    Label(text, systemImage: "checkmark.circle")
                        .foregroundStyle(Tz.okText)
                case .failed, .unreachable, .badAddress:
                    Label(text, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Tz.error)
                case .testing:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(text)
                    }
                    .foregroundStyle(Tz.textSecondary)
                }
            }
        }
        .font(Fonts.caption)
        .frame(minHeight: 20, alignment: .leading)
    }
}
