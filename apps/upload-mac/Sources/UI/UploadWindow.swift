import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 上传窗口：一屏四块——上传区、已选图片、老师的话 + 日期、主按钮。
/// 全窗都是拖拽目标（不只是中间虚线框）。
struct UploadWindow: View {
    @EnvironmentObject private var store: UploadStore

    @State private var isDropTargeted = false
    @State private var showImporter = false
    @AppStorage(DefaultsKey.lastUploadCount) private var lastCount = 0
    @AppStorage(DefaultsKey.lastUploadAt) private var lastAt = 0.0
    @AppStorage(DefaultsKey.lastUploadDuplicate) private var lastDuplicate = false

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bgBase.ignoresSafeArea()

            VStack(spacing: 0) {
                if store.isOffline {
                    connectionBanner
                }
                header
                dropZone
                if let hint = store.hintMessage {
                    hintLine(hint)
                }
                if !store.images.isEmpty {
                    thumbnailStrip
                }
                dateRow
                noteField
                Spacer(minLength: Space.s3)
                submitButton
                Text(L10n.string("upload.window.leaveEarly"))
                    .font(Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, Space.s2)
                receipt
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s4)

            if let toast = store.toast {
                toastView(toast)
            }
        }
        .frame(width: 560, height: 700)
        .background(Theme.bgBase)
        .disabled(store.isUploading)
        .onDrop(
            of: [UTType.fileURL, UTType.image],
            delegate: ImageDropDelegate(store: store, isTargeted: $isDropTargeted)
        )
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                store.add(sources: urls.map { ImageSource(fileURL: $0) })
            }
        }
        .onAppear {
            store.refreshHealth()
        }
        .animation(.easeOut(duration: 0.2), value: store.toast)
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(spacing: Space.s2) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("app.name"))
                    .font(Fonts.title)
                    .foregroundStyle(Theme.textPrimary)
                Text(connectionLabel)
                    .font(Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Space.s2)
            Button {
                WindowManager.shared.showSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(L10n.string("settings.title"))
        }
        .padding(.bottom, Space.s5)
    }

    private var connectionLabel: String {
        switch store.health {
        case .ok: return L10n.string("upload.connection.ok")
        case .down: return L10n.string("upload.connection.down")
        case .checking: return L10n.string("upload.connection.checking")
        case .unknown: return L10n.string("app.subtitle")
        }
    }

    private var receipt: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Divider().overlay(Theme.line)
            if lastAt > 0 {
                HStack {
                    Text(lastDuplicate
                         ? L10n.string("upload.receipt.duplicate")
                         : L10n.count(lastCount,
                                      one: "upload.receipt.count.one",
                                      other: "upload.receipt.count"))
                    Spacer()
                    // 24 小时制，和菜单栏、协议里的示例一致（docs/12-国际化.md §5）
                    Text(Self.timeFormatter.string(from: Date(timeIntervalSince1970: lastAt)))
                }
            } else {
                Text(L10n.string("upload.receipt.idle"))
            }
        }
        .font(Fonts.caption)
        .foregroundStyle(Theme.textSecondary)
        .padding(.top, Space.s4)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// 服务不通时的黄条。只在健康检查明确失败后出现，避免打开窗口时闪一下。
    private var connectionBanner: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(L10n.string("error.offline"))
                .font(Fonts.caption)
            Spacer(minLength: Space.s2)
            Button {
                WindowManager.shared.showSettingsWindow()
            } label: {
                Text(L10n.string("upload.banner.settings"))
                    .font(Fonts.caption.weight(.semibold))
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.warnText)
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Theme.warnSurface)
        )
        .padding(.bottom, Space.s3)
    }

    // MARK: - 上传区

    private var dropZone: some View {
        let compact = !store.images.isEmpty
        return ZStack {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(isDropTargeted ? Theme.accent.opacity(0.12) : Theme.bgSurface)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Theme.accent : Theme.line,
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1.5, dash: [7, 6])
                )

            if compact {
                VStack(spacing: Space.s2) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(L10n.string("upload.dropZone.continue"))
                        .font(Fonts.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L10n.string("upload.dropZone.continueHint"))
                        .font(Fonts.caption)
                        .foregroundStyle(Theme.textDim)
                }
            } else {
                VStack(spacing: Space.s2) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Theme.textSecondary)
                    Text(L10n.string("upload.title"))
                        .font(Fonts.dropTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(L10n.string("upload.dropZone.hint"))
                        .font(Fonts.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(L10n.string("upload.dropZone.tip"))
                        .font(Fonts.hint)
                        .foregroundStyle(Theme.textDim)
                }
                .padding(Space.s3)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 160,
            maxHeight: 160
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onTapGesture { showImporter = true }
        .help(L10n.string("upload.dropZone.help"))
    }

    private func hintLine(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
            Text(text)
                .font(Fonts.hint)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.error)
        .padding(.top, Space.s2)
    }

    // MARK: - 已选图片

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(store.images) { image in
                    thumbCell(image)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 108)
        .padding(.top, Space.s2)
    }

    private func thumbCell(_ image: SelectedImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 154, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )

            Button {
                store.remove(image)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.black.opacity(0.62)))
            }
            .buttonStyle(.plain)
            .padding(3)
            .help(L10n.string("image.remove"))
        }
        .frame(width: 154, height: 96)
        .help("\(image.sourceName) · \(Int(image.pixelSize.width))×\(Int(image.pixelSize.height))")
    }

    // MARK: - 备注 + 日期

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("note.label"))
                .font(Fonts.caption)
                .foregroundStyle(Theme.textSecondary)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Theme.bgRaised)
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)

                TextEditor(text: $store.note)
                    .font(Fonts.body)
                    .foregroundColor(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                if store.note.isEmpty {
                    Text(L10n.string("note.placeholder"))
                        .font(Fonts.body)
                        .foregroundStyle(Theme.textDim)
                        .padding(.leading, 13)
                        .padding(.top, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 56)
        }
        .padding(.top, Space.s3)
    }

    private var dateRow: some View {
        HStack(spacing: Space.s2) {
            Text(L10n.string("date.label"))
                .font(Fonts.caption)
                .foregroundStyle(Theme.textSecondary)

            DatePicker(
                "",
                selection: $store.date,
                in: Date.distantPast...Date(),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .environment(\.locale, Locale.current)
            .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai") ?? .current)

            Spacer(minLength: 0)

            Text(store.dateCaption)
                .font(Fonts.caption)
                .foregroundStyle(Theme.textDim)
        }
        .padding(.top, Space.s2)
    }

    // MARK: - 主按钮

    private var submitButton: some View {
        Button {
            store.submit()
        } label: {
            Text(store.submitTitle)
                .font(Fonts.button)
                .foregroundStyle(store.didFail ? Color.white : Theme.accentInk)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(store.didFail ? Theme.error : Theme.accent)
                )
        }
        .buttonStyle(.plain)
        .disabled(store.images.isEmpty || store.isUploading || store.preparationCount > 0)
        .opacity(buttonOpacity)
        .padding(.top, Space.s3)
    }

    private var buttonOpacity: Double {
        if store.didFail { return 1 }
        if store.images.isEmpty { return 0.45 }
        if store.isUploading { return 0.7 }
        return 1
    }

    // MARK: - Toast

    private func toastView(_ toast: Toast) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: toast.kind == .success ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(toast.kind == .success ? Theme.okText : Theme.accent)
            Text(toast.text)
                .font(Fonts.caption)
                .foregroundStyle(toast.kind == .success ? Theme.okText : Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(toast.kind == .success ? Theme.okSurface : Theme.bgSurface)
                .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s3)
        .transition(.move(edge: .top).combined(with: .opacity))
        .allowsHitTesting(false)
    }
}
