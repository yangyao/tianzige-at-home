import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 相册多选。用 PHPicker，不申请完整相册权限，用户选哪张才读哪张。
/// 回调里统一回原始 Data（可能是 HEIC），压缩交给 ImageCompressor。
struct PhotoPicker: UIViewControllerRepresentable {
    let selectionLimit: Int
    let onFinish: ([Data]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = max(1, selectionLimit)
        // 保持原始编码，避免系统在选中时就转码，压缩由我们统一做
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate, @unchecked Sendable {
        private let onFinish: ([Data]) -> Void

        init(onFinish: @escaping ([Data]) -> Void) {
            self.onFinish = onFinish
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // 取消时也要回一次空数组，让外层把 sheet 的 binding 复位
            guard !results.isEmpty else {
                Task { @MainActor in
                    self.onFinish([])
                }
                return
            }

            Task {
                var payloads: [Data] = []
                for result in results {
                    if let data = await Self.loadData(from: result.itemProvider) {
                        payloads.append(data)
                    }
                }
                let loaded = payloads
                await MainActor.run {
                    self.onFinish(loaded)
                }
            }
        }

        private static func loadData(from provider: NSItemProvider) async -> Data? {
            let typeIdentifier = UTType.image.identifier
            guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else { return nil }

            return await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
        }
    }
}
