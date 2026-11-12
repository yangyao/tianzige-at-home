import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum Health: Equatable {
    case unknown
    case checking
    case ok(version: String?)
    case down
}

struct Toast: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case info
    }

    let id = UUID()
    let text: String
    let kind: Kind
}

/// 上传窗口的全部状态。单例：菜单栏、上传窗口、设置窗口共用一份。
/// 所有方法都在主线程调用（SwiftUI / AppKit 侧）；只有 async 方法在尾部回到 MainActor 写状态。
@MainActor
final class UploadStore: ObservableObject {
    static let shared = UploadStore()
    static let maxImages = 6

    @Published private(set) var images: [SelectedImage] = []
    @Published var note: String = "" {
        didSet {
            // 协议 note maxLength 500
            if note.count > 500 { note = String(note.prefix(500)) }
        }
    }
    @Published var date: Date = Date()

    @Published private(set) var isUploading = false
    /// 非空 = 上次失败，按钮变红，图片保留。
    @Published private(set) var failureMessage: String?
    /// 上传区下面那行红字（超 6 张、打不开、格式不支持）。
    @Published private(set) var limitMessage: String?
    @Published private(set) var toast: Toast?

    @Published private(set) var health: Health = .unknown
    /// 黄条独立于 health：重新检查期间（.checking）黄条不闪，只有真正连上才撤掉。
    @Published private(set) var isOffline = false

    private var healthTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    private init() {}

    // MARK: - 计算属性（给视图用）

    /// 设置窗口用 @AppStorage 写 UserDefaults，这里每次现读，保持单一真源。
    var baseURLString: String {
        UserDefaults.standard.string(forKey: DefaultsKey.nasBaseURL) ?? APIClient.defaultBase
    }

    var isCheckingHealth: Bool {
        if case .checking = health { return true }
        return false
    }

    var didFail: Bool { failureMessage != nil }

    /// 上传区下面那行提示：失败信息优先，其次才是超限提示。
    /// 连不上时顶部已经有黄条，红字不再重复同一句。
    var hintMessage: String? {
        if isOffline { return limitMessage }
        return failureMessage ?? limitMessage
    }

    var submitTitle: String {
        if isUploading { return "上传中…" }
        if didFail { return "没传上去，点这里重试" }
        if images.isEmpty { return "上传" }
        return "上传（\(images.count) 张）"
    }

    /// 日期行右边那句「今天 / 昨天 / 11月10日」
    var dateCaption: String {
        if Self.shanghaiCalendar.isDateInToday(date) { return "今天" }
        if Self.shanghaiCalendar.isDateInYesterday(date) { return "昨天" }
        return Self.monthDayFormatter.string(from: date)
    }

    // MARK: - 加图 / 删图

    func add(sources: [ImageSource]) {
        guard !sources.isEmpty else { return }
        limitMessage = nil
        failureMessage = nil

        let room = Self.maxImages - images.count
        guard room > 0 else {
            limitMessage = "一次最多传 6 张，先删掉几张再放"
            return
        }

        let accepted = Array(sources.prefix(room))
        let overflow = sources.count - accepted.count

        Task {
            // 解码 + 缩放 + 编码放到后台，窗口不卡。PreparedImage 是纯数据，跨线程安全。
            let prepared = await Task.detached(priority: .userInitiated) { () -> [PreparedImage] in
                accepted.compactMap { source in
                    autoreleasepool { ImageProcessor.prepare(source) }
                }
            }.value

            var added = 0
            for item in prepared {
                guard images.count < Self.maxImages else {
                    limitMessage = "一次最多传 6 张"
                    break
                }
                guard let thumbnail = NSImage(data: item.thumbnailJPEG) else { continue }
                images.append(
                    SelectedImage(
                        data: item.jpeg,
                        thumbnail: thumbnail,
                        pixelSize: item.pixelSize,
                        sourceName: item.name
                    )
                )
                added += 1
            }

            if overflow > 0 {
                limitMessage = "一次最多传 6 张，多出来的 \(overflow) 张没放进来"
            } else if added < accepted.count {
                let failed = accepted.count - added
                limitMessage = failed == 1 ? "有 1 张打不开，换一张试试" : "有 \(failed) 张打不开，换一张试试"
            }
        }
    }

    func remove(_ image: SelectedImage) {
        images.removeAll { $0.id == image.id }
        limitMessage = nil
        failureMessage = nil
    }

    /// 拖拽进来的 NSItemProvider（Finder 图片文件 / 浏览器图片）
    func acceptDrop(providers: [NSItemProvider]) {
        Task {
            var sources: [ImageSource] = []
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                   let url = await Self.loadFileURL(from: provider) {
                    sources.append(ImageSource(fileURL: url))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                          let data = await Self.loadImageData(from: provider) {
                    sources.append(ImageSource(data: data, name: "拖进来的图片"))
                }
            }
            add(sources: sources)
        }
    }

    func pasteFromClipboard() {
        let sources = ClipboardReader.sources()
        add(sources: sources)
    }

    // MARK: - 上传

    func submit() {
        guard !isUploading, !images.isEmpty else { return }
        guard let base = APIClient.normalizedBase(baseURLString) else {
            failureMessage = IngestError.badAddress.userMessage
            return
        }

        let payload = images.map(\.data)
        let noteText = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateText = Self.apiDateFormatter.string(from: date)

        isUploading = true
        failureMessage = nil
        limitMessage = nil

        Task {
            do {
                // 拿到 202 就结束，不轮询识别结果。
                let response = try await APIClient(baseURL: base)
                    .ingest(images: payload, note: noteText, date: dateText)
                finishSuccess(response)
            } catch {
                finishFailure(error)
            }
        }
    }

    private func finishSuccess(_ response: IngestResponse) {
        isUploading = false
        images = []
        note = ""
        date = Date()
        limitMessage = nil
        failureMessage = nil

        if response.duplicateOf != nil {
            showToast("这些图片之前传过了，没有重复入库", kind: .info)
        } else {
            showToast("收到 \(response.imageCount) 张，处理完电视上就有", kind: .success)
        }
        recordLastUpload(count: response.imageCount, duplicate: response.duplicateOf != nil)
        // 能传上去说明网络是通的
        health = .ok(version: nil)
        isOffline = false
    }

    private func finishFailure(_ error: Error) {
        isUploading = false
        let ingestError = error as? IngestError ?? .malformed
        failureMessage = ingestError.userMessage
        if case .offline = ingestError {
            // 立刻挂黄条；不在失败流程里再发一次健康检查，避免黄条闪一下又消失。
            health = .down
            isOffline = true
        }
    }

    private func showToast(_ text: String, kind: Toast.Kind) {
        toastTask?.cancel()
        toast = Toast(text: text, kind: kind)
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.toast = nil
        }
    }

    /// 菜单栏的「上次：✓ N 张 · 17:32」直接读这三个键（@AppStorage），跨启动保留。
    private func recordLastUpload(count: Int, duplicate: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(count, forKey: DefaultsKey.lastUploadCount)
        defaults.set(Date().timeIntervalSince1970, forKey: DefaultsKey.lastUploadAt)
        defaults.set(duplicate, forKey: DefaultsKey.lastUploadDuplicate)
    }

    // MARK: - 连通性

    func refreshHealth(force: Bool = false) {
        guard let base = APIClient.normalizedBase(baseURLString) else {
            health = .down
            isOffline = true
            return
        }
        if isCheckingHealth && !force { return }
        if case .ok = health, !force { return }

        healthTask?.cancel()
        health = .checking

        healthTask = Task { [weak self] in
            let result: Health
            do {
                let response = try await APIClient(baseURL: base).health()
                result = response.ok ? .ok(version: response.version) : .down
            } catch {
                result = .down
            }
            guard !Task.isCancelled, let self else { return }
            // 这期间用户改了地址，旧结果作废
            if APIClient.normalizedBase(self.baseURLString) == base {
                self.health = result
                self.isOffline = (result == .down)
            }
        }
    }

    // MARK: - NSItemProvider 异步加载

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let nsurl = item as? NSURL {
                    url = nsurl as URL
                } else if let direct = item as? URL {
                    url = direct
                } else {
                    url = nil
                }
                continuation.resume(returning: url)
            }
        }
    }

    private static func loadImageData(from provider: NSItemProvider) async -> Data? {
        // 尽量用 provider 实际登记的具体类型（public.jpeg / public.png …），
        // 直接要 public.image 有的 App 不认。
        let typeID = provider.registeredTypeIdentifiers.first {
            UTType($0)?.conforms(to: .image) == true
        } ?? UTType.image.identifier

        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            provider.loadDataRepresentation(forTypeIdentifier: typeID) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    // MARK: - 时间

    /// 协议的日期一律是 Asia/Shanghai 的那一天（docs/05-协议.md §6）。
    static let shanghaiCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }()

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}
