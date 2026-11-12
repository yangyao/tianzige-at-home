import SwiftUI
import UniformTypeIdentifiers

/// 全窗拖拽目标。拖拽支持两类：
/// - Finder 里的图片文件（public.file-url）
/// - 浏览器 / 其他 App 直接给的图片数据（public.image）
struct ImageDropDelegate: DropDelegate {
    let store: UploadStore
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL, UTType.image])
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let providers = info.itemProviders(for: [UTType.fileURL, UTType.image])
        guard !providers.isEmpty else { return false }
        // DropDelegate 的方法不在主线程标注里，显式跳回 MainActor 改状态。
        Task { @MainActor in
            store.acceptDrop(providers: providers)
        }
        return true
    }
}
