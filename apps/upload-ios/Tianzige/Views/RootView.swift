import SwiftUI
import UIKit

/// 唯一的主界面：上传区 → 已选图片 → 老师的话 → 日期 → 底部主按钮。
/// 没有「最近上传」，没有查看、重跑、删除——手机只负责送进来。
struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel = UploadViewModel()

    @State private var showsSettings = false
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bgBase.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if !viewModel.isServerReachable {
                    offlineBanner
                }

                ScrollView {
                    content
                        .padding(.horizontal, Theme.Space.s5)
                        .padding(.top, Theme.Space.s5)
                        .padding(.bottom, Theme.Space.s6)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }

            if let toast = viewModel.toast {
                ToastView(message: toast)
                    .padding(.horizontal, Theme.Space.s5)
                    .padding(.bottom, Theme.Space.s4 + 72)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture {
                        viewModel.dismissToast()
                    }
            }
        }
        .disabled(viewModel.phase == .uploading)
        .animation(.easeOut(duration: 0.2), value: viewModel.toast)
        .sheet(isPresented: $showsSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .sheet(isPresented: $showsPhotoPicker) {
            PhotoPicker(selectionLimit: viewModel.remainingSlots) { dataList in
                showsPhotoPicker = false
                Task { await viewModel.addImages(from: dataList) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { data in
                showsCamera = false
                if let data {
                    Task { await viewModel.addImages(from: [data]) }
                }
            }
            .ignoresSafeArea()
        }
        .task {
            await viewModel.checkHealth()
            viewModel.refreshClipboardHint()
            #if DEBUG
            if ProcessInfo.processInfo.environment["TIANZIGE_LAYOUT_PHOTO"] == "1",
               let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
               let data = try? Data(contentsOf: documents.appendingPathComponent("layout-check.jpg")) {
                await viewModel.addImages(from: [data])
            }
            #endif
        }
        .onChange(of: settings.baseURLString) { _ in
            viewModel.scheduleHealthCheck()
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            Task {
                await viewModel.checkHealth()
                viewModel.refreshClipboardHint()
            }
        }
    }

    // MARK: - 标题行

    private var header: some View {
        HStack(alignment: .center) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("app.name"))
                    .font(Theme.Fonts.title)
                    .foregroundColor(Theme.textPrimary)
                Text(L10n.string("app.subtitle"))
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.textDim)
            }

            Spacer()

            Button {
                showsSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(L10n.string("settings.title"))
        }
        .padding(.horizontal, Theme.Space.s4)
        .padding(.top, Theme.Space.s3)
        .padding(.bottom, Theme.Space.s2)
    }

    // MARK: - 连不上 NAS 的黄条

    private var offlineBanner: some View {
        Button {
            showsSettings = true
        } label: {
            HStack(spacing: Theme.Space.s2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.string("error.offline"))
                    .font(Theme.Fonts.caption)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(Theme.stateWarn)
            .padding(.horizontal, Theme.Space.s4)
            .padding(.vertical, Theme.Space.s2 + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.stateWarn.opacity(0.14))
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.string("root.offlineBanner.hint"))
    }

    // MARK: - 主体

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s5) {
            uploadArea

            if let message = viewModel.inlineMessage {
                Text(message)
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.stateError)
            }

            if viewModel.clipboardHasImage {
                clipboardRow
            }

            if !viewModel.images.isEmpty {
                imageStrip
            }

            dateRow
            Divider().overlay(Theme.line)
            noteField
        }
    }

    // MARK: - 上传区

    private var uploadArea: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s5) {
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                Text(L10n.string("upload.title"))
                    .font(Theme.Fonts.sectionTitle)
                    .foregroundColor(Theme.textPrimary)
                Text(L10n.string("upload.subtitle"))
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.textDim)
            }

            HStack(spacing: Theme.Space.s3) {
                sourceButton(title: L10n.string("upload.fromLibrary"), systemImage: "photo.on.rectangle") {
                    guard viewModel.remainingSlots > 0 else {
                        viewModel.inlineMessage = viewModel.tooManyImagesMessage
                        return
                    }
                    showsPhotoPicker = true
                }

                sourceButton(title: L10n.string("upload.takePhoto"), systemImage: "camera.fill") {
                    guard viewModel.remainingSlots > 0 else {
                        viewModel.inlineMessage = viewModel.tooManyImagesMessage
                        return
                    }
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                        viewModel.inlineMessage = L10n.string("error.noCamera")
                        return
                    }
                    showsCamera = true
                }
            }
            .padding(.top, Theme.Space.s1)

            if viewModel.isCompressing {
                HStack(spacing: Theme.Space.s2) {
                    ProgressView()
                        .tint(Theme.textSecondary)
                    Text(L10n.string("upload.compressing"))
                        .font(Theme.Fonts.caption)
                        .foregroundColor(Theme.textDim)
                }
            }
        }
        .frame(maxWidth: .infinity)

    }

    private func sourceButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s2) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(Theme.Fonts.bodySemibold)
            }
            .foregroundColor(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Theme.bgRaised)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - 剪贴板提示

    private var clipboardRow: some View {
        HStack(spacing: Theme.Space.s3) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Theme.textSecondary)

            Text(L10n.string("clipboard.hint"))
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button(L10n.string("clipboard.add")) {
                Task { await viewModel.addClipboardImage() }
            }
            .font(Theme.Fonts.bodySemibold)
            .foregroundColor(Theme.accent)

            Button {
                viewModel.dismissClipboardHint()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textDim)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("clipboard.dismiss"))
        }
        .padding(.horizontal, Theme.Space.s3)
        .padding(.vertical, Theme.Space.s2)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    // MARK: - 已选图片条

    private var imageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s3) {
                ForEach(viewModel.images) { image in
                    thumbnail(image)
                }

                if viewModel.remainingSlots > 0 {
                    addMoreTile
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func thumbnail(_ image: SelectedImage) -> some View {
        Image(uiImage: image.thumbnail)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 136, height: 104)
            .background(Theme.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        viewModel.remove(image)
                    }
                } label: {
                    // 照片上的浮层，固定黑底白叉，深色照片上也看得见
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel(L10n.string("image.remove"))
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
    }

    private var addMoreTile: some View {
        Button {
            showsPhotoPicker = true
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                Text(L10n.count(viewModel.remainingSlots,
                                one: "image.remaining.one",
                                other: "image.remaining"))
                    .font(Theme.Fonts.min)
            }
            .foregroundColor(Theme.textDim)
            .frame(width: 76, height: 76)
            .background(Theme.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - 老师的话

    private var noteField: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Text(L10n.string("note.label"))
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.textSecondary)

            TextField(
                L10n.string("note.placeholder"),
                text: Binding(
                    get: { viewModel.note },
                    set: { viewModel.note = String($0.prefix(UploadViewModel.maxNoteLength)) }
                ),
                axis: .vertical
            )
            .font(Theme.Fonts.body)
            .foregroundColor(Theme.textPrimary)
            .lineLimit(2...4)
            .padding(Theme.Space.s3)
            .background(Theme.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
        }
    }

    // MARK: - 日期

    private var dateRow: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    viewModel.isDatePickerExpanded.toggle()
                }
            } label: {
                HStack(spacing: Theme.Space.s3) {
                    Text(L10n.string("date.label"))
                        .font(Theme.Fonts.body)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Spacer()

                    Text(DateString.dayLabel(for: viewModel.selectedDate))
                        .font(Theme.Fonts.bodySemibold)
                        .foregroundColor(Theme.accent)

                    Text(DateString.apiDate(from: viewModel.selectedDate))
                        .font(Theme.Fonts.caption)
                        .monospacedDigit()
                        .foregroundColor(Theme.textDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Image(systemName: viewModel.isDatePickerExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.textDim)
                }
                .padding(.horizontal, Theme.Space.s4)
                .frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())

            if viewModel.isDatePickerExpanded {
                DatePicker(
                    L10n.string("date.picker"),
                    selection: $viewModel.selectedDate,
                    in: viewModel.dateRange,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Space.s3)
                .padding(.bottom, Theme.Space.s2)
            }
        }
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    // MARK: - 底部主按钮

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.line)
                .frame(height: 1)

            Button {
                Task { await viewModel.upload() }
            } label: {
                HStack(spacing: Theme.Space.s2) {
                    if viewModel.phase == .uploading {
                        ProgressView()
                            .tint(buttonForeground)
                    }
                    Text(buttonTitle)
                        .font(Theme.Fonts.button)
                }
                .foregroundColor(buttonForeground)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(buttonBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .disabled(!viewModel.canUpload)
            .accessibilityLabel(buttonTitle)
            .padding(.horizontal, Theme.Space.s5)
            .padding(.top, Theme.Space.s3)
            .padding(.bottom, Theme.Space.s2)

            Text(L10n.string("footer.leaveEarly"))
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.textSecondary)
                .padding(.bottom, Theme.Space.s3)
        }
        .background(Theme.bgBase.ignoresSafeArea(edges: .bottom))
    }

    private var buttonTitle: String {
        switch viewModel.phase {
        case .uploading:
            return L10n.string("upload.uploading")
        case .failed:
            return L10n.string("upload.retry")
        case .idle:
            guard !viewModel.images.isEmpty else { return L10n.string("upload.button") }
            return L10n.count(viewModel.images.count,
                              one: "upload.button.count.one",
                              other: "upload.button.count")
        }
    }

    private var buttonBackground: Color {
        switch viewModel.phase {
        case .uploading:
            return Theme.primaryAction.opacity(0.55)
        case .failed:
            return Theme.stateError
        case .idle:
            return viewModel.images.isEmpty ? Theme.bgRaised : Theme.primaryAction
        }
    }

    private var buttonForeground: Color {
        switch viewModel.phase {
        case .uploading:
            return .white
        case .failed:
            return .white
        case .idle:
            return viewModel.images.isEmpty ? Theme.textDim : .white
        }
    }
}

#if DEBUG
struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
            .environmentObject(AppSettings.shared)
    }
}
#endif
