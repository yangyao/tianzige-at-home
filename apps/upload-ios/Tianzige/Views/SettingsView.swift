import SwiftUI

/// 设置页只有一件事：NAS 地址 + 测试连接。
/// 地址存 UserDefaults，改完立刻生效，下次上传就用新地址。
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var testState: TestState = .idle
    @FocusState private var addressFocused: Bool

    private enum TestState: Equatable {
        case idle
        case testing
        case success(version: String)
        case failure(message: String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgBase.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s5) {
                        addressSection
                        testSection
                        hintSection
                    }
                    .padding(Theme.Space.s5)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        addressFocused = false
                        dismiss()
                    }
                    .foregroundColor(Theme.accent)
                }
            }
            .toolbarBackground(Theme.bgBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - 地址

    private var addressSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Text("NAS 地址")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.textSecondary)

            TextField("http://nas.local:8080", text: $settings.baseURLString)
                .font(Theme.Fonts.body)
                .foregroundColor(Theme.textPrimary)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($addressFocused)
                .submitLabel(.done)
                .onSubmit {
                    addressFocused = false
                }
                .padding(Theme.Space.s3)
                .background(Theme.bgSurface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
                .onChange(of: settings.baseURLString) { _ in
                    // 地址一改，上一次的连接结果就作废
                    testState = .idle
                }

            Text("填家里 NAS 的局域网地址，例如 http://192.168.1.20:8080")
                .font(Theme.Fonts.min)
                .foregroundColor(Theme.textDim)
        }
    }

    // MARK: - 测试连接

    private var testSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            Button {
                Task { await testConnection() }
            } label: {
                HStack(spacing: Theme.Space.s2) {
                    if testState == .testing {
                        ProgressView()
                            .tint(Theme.accentInk)
                    }
                    Text("测试连接")
                        .font(Theme.Fonts.bodySemibold)
                }
                .foregroundColor(Theme.accentInk)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .disabled(testState == .testing || !AppSettings.isValid(settings.baseURLString))
            .opacity(AppSettings.isValid(settings.baseURLString) ? 1 : 0.5)

            switch testState {
            case .idle:
                EmptyView()
            case .testing:
                Text("正在连接…")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.textDim)
            case let .success(version):
                resultLine(
                    text: "已连接 · 服务端版本 \(version)",
                    color: Theme.stateOK,
                    systemImage: "checkmark.circle.fill"
                )
            case let .failure(message):
                resultLine(
                    text: message,
                    color: Theme.stateError,
                    systemImage: "exclamationmark.circle.fill"
                )
            }
        }
    }

    private func resultLine(text: String, color: Color, systemImage: String) -> some View {
        HStack(spacing: Theme.Space.s2) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(Theme.Fonts.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(color)
    }

    // MARK: - 说明

    private var hintSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Text("这个 App 只负责把照片传上去。传完就可以切走，电视上自己会出来，不用等。")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            Text("只在家里局域网里用，照片不会出公网。")
                .font(Theme.Fonts.min)
                .foregroundColor(Theme.textDim)
        }
        .padding(.top, Theme.Space.s2)
    }

    // MARK: - 行为

    @MainActor
    private func testConnection() async {
        addressFocused = false
        testState = .testing

        do {
            let health = try await APIClient(baseURL: settings.baseURL).health()
            guard health.ok else {
                testState = .failure(message: "连不上 NAS，检查地址或网络")
                return
            }
            testState = .success(version: health.version)
        } catch let error as APIError {
            let message = error.isConnectionProblem ? "连不上 NAS，检查地址或网络" : error.userMessage
            testState = .failure(message: message)
        } catch {
            testState = .failure(message: "连不上 NAS，检查地址或网络")
        }
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AppSettings.shared)
    }
}
#endif
