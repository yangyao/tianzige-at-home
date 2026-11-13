import AppKit

/// 剪贴板读取。
/// 两种常见形态都要认：
/// 1. Finder 里 ⌘C 复制的图片文件 → 剪贴板里是 file URL
/// 2. ⌘⇧4 截图 / 浏览器里复制图片 → 剪贴板里是 NSImage（TIFF/PNG）
@MainActor
enum ClipboardReader {

    static func sources() -> [ImageSource] {
        let pasteboard = NSPasteboard.general

        if let urls = fileURLs(in: pasteboard), !urls.isEmpty {
            return urls.map { ImageSource(fileURL: $0) }
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            return images.compactMap { image in
                // 在主线程序列化成 TIFF，后台线程只碰 Data。
                guard let tiff = image.tiffRepresentation else { return nil }
                return ImageSource(data: tiff, name: L10n.string("image.source.clipboard"))
            }
        }
        return []
    }

    static func hasImage() -> Bool {
        let pasteboard = NSPasteboard.general
        if let urls = fileURLs(in: pasteboard), !urls.isEmpty { return true }
        return pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    static func hasText() -> Bool {
        let pasteboard = NSPasteboard.general
        return pasteboard.canReadObject(forClasses: [NSString.self], options: nil)
            || pasteboard.string(forType: .string) != nil
    }

    private static func fileURLs(in pasteboard: NSPasteboard) -> [URL]? {
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return nil }
        let images = urls.filter { ImageProcessor.isSupportedImage($0) }
        return images.isEmpty ? nil : images
    }
}
