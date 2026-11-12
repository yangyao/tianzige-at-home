import SwiftUI
import UIKit

/// 主界面的全部状态。刻意只做一件事：攒图 → 传 → 清空。
@MainActor
final class UploadViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case uploading
        /// 失败但图片还在，主按钮变红变成「重试」
        case failed
    }

    /// 协议：单批 1–6 张。
    static let maxImages = 6
    static let maxNoteLength = 500
    static let toastDuration: UInt64 = 6_000_000_000

    @Published private(set) var images: [SelectedImage] = []
    @Published var note = ""
    @Published var selectedDate: Date = DateString.today
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var toast: ToastMessage?
    @Published private(set) var isServerReachable = true
    @Published private(set) var isCompressing = false
    @Published private(set) var clipboardHasImage = false
    @Published var inlineMessage: String?
    @Published var isDatePickerExpanded = false

    private let settings = AppSettings.shared
    private var toastTask: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?

    // MARK: - 派生状态

    var remainingSlots: Int {
        max(0, Self.maxImages - images.count)
    }

    var canUpload: Bool {
        !images.isEmpty && phase != .uploading
    }

    var dateRange: ClosedRange<Date> {
        DateString.earliestSelectableDay...Date()
    }

    var tooManyImagesMessage: String {
        "一次最多 \(Self.maxImages) 张，先删掉几张再选"
    }

    // MARK: - 选图

    /// 相册 / 拍照 / 剪贴板最终都汇到这里。传入未压缩的原始数据。
    func addImages(from dataList: [Data]) async {
        guard !dataList.isEmpty else { return }

        let slots = remainingSlots
        guard slots > 0 else {
            inlineMessage = tooManyImagesMessage
            return
        }

        let accepted = Array(dataList.prefix(slots))
        inlineMessage = nil
        isCompressing = true
        let compressed = await Self.compressInBackground(accepted)
        isCompressing = false

        guard !compressed.isEmpty else {
            inlineMessage = "这几张读不出来，换几张试试"
            return
        }

        images.append(contentsOf: compressed.map { self.makeSelectedImage($0) })

        if dataList.count > slots {
            inlineMessage = "一次最多 \(Self.maxImages) 张，多的这次没放进来"
        }
        refreshClipboardHint()
    }

    func remove(_ image: SelectedImage) {
        images.removeAll { $0.id == image.id }
        refreshClipboardHint()
    }

    private func makeSelectedImage(_ compressed: CompressedImage) -> SelectedImage {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        return SelectedImage(
            jpegData: compressed.jpegData,
            thumbnail: UIImage(data: compressed.thumbnailData) ?? UIImage(),
            filename: "photo-\(suffix).jpg"
        )
    }

    /// 压缩放到后台，6 张 4000px 的图在旧机器上要几百毫秒，不能卡主线程。
    private static func compressInBackground(_ dataList: [Data]) async -> [CompressedImage] {
        await Task.detached(priority: .userInitiated) {
            dataList.compactMap { ImageCompressor.compress($0) }
        }.value
    }

    // MARK: - 上传

    func upload() async {
        guard canUpload else { return }

        phase = .uploading
        inlineMessage = nil

        let files = images.map {
            UploadFile(data: $0.jpegData, filename: $0.filename, mimeType: "image/jpeg")
        }
        let note = self.note
        let date = DateString.apiDate(from: selectedDate)
        let client = APIClient(baseURL: settings.baseURL)

        do {
            let response = try await client.ingest(files: files, note: note, date: date)
            applySuccess(response)
        } catch let error as APIError {
            if error.isConnectionProblem {
                isServerReachable = false
            }
            phase = .failed
            showToast(ToastMessage(text: error.userMessage, kind: .error))
        } catch {
            phase = .failed
            showToast(ToastMessage(text: "这次没传上去，点一下再试", kind: .error))
        }
    }

    /// 铁律：202 就结束。清空表单、弹一句 toast，让用户走人，绝不轮询识别结果。
    private func applySuccess(_ response: IngestResponse) {
        phase = .idle
        images = []
        note = ""
        selectedDate = DateString.today
        inlineMessage = nil
        clipboardHasImage = false
        isServerReachable = true

        if response.duplicateOf != nil {
            showToast(ToastMessage(text: "这些图片之前传过了，没有重复入库", kind: .info))
        } else {
            showToast(ToastMessage(text: "收到 \(response.imageCount) 张，处理完电视上就有", kind: .success))
        }
    }

    // MARK: - 服务可达性

    func checkHealth() async {
        do {
            let health = try await APIClient(baseURL: settings.baseURL).health()
            isServerReachable = health.ok
        } catch {
            isServerReachable = false
        }
    }

    /// 设置页改地址时防抖：停止输入 400ms 后再测，别一个键一次请求。
    func scheduleHealthCheck() {
        healthTask?.cancel()

        guard AppSettings.isValid(settings.baseURLString) else {
            isServerReachable = false
            return
        }

        healthTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await checkHealth()
        }
    }

    // MARK: - 剪贴板

    /// 只判断「有没有」，不读内容，所以不会触发 iOS 的粘贴提示。
    func refreshClipboardHint() {
        guard remainingSlots > 0 else {
            clipboardHasImage = false
            return
        }
        clipboardHasImage = UIPasteboard.general.hasImages
    }

    /// 用户点了「添加」才真正读。这一步系统会弹一次粘贴提示，是我们主动换来的。
    func addClipboardImage() async {
        clipboardHasImage = false

        guard let image = UIPasteboard.general.image,
              let data = image.jpegData(compressionQuality: 1.0) else {
            inlineMessage = "剪贴板里没有能用的图片"
            return
        }

        await addImages(from: [data])
        // addImages 会重新检测剪贴板，这里再收一次，避免刚加完又问一遍
        clipboardHasImage = false
    }

    func dismissClipboardHint() {
        clipboardHasImage = false
    }

    // MARK: - Toast

    func showToast(_ message: ToastMessage) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.toastDuration)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }
}
