import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 送进列表的一张图（只在主线程用）：已经压好的 JPEG + 一个小缩略图。
struct SelectedImage: Identifiable, Equatable {
    let id = UUID()
    /// 实际发出去的 JPEG（最长边 2048、质量 0.85）
    let data: Data
    /// 列表里显示用的小图（最长边 320），避免 6 张 2048px 大图同时驻留内存
    let thumbnail: NSImage
    let pixelSize: CGSize
    let sourceName: String

    static func == (lhs: SelectedImage, rhs: SelectedImage) -> Bool {
        lhs.id == rhs.id
    }
}

/// 后台线程处理完的纯数据，可以安全跨线程（不碰 AppKit）。
struct PreparedImage: Sendable {
    let jpeg: Data
    let thumbnailJPEG: Data
    let pixelSize: CGSize
    let name: String
}

/// 图片来源。只带 URL / Data，不带 NSImage——真正解码放到后台线程做。
struct ImageSource: Sendable {
    enum Storage: Sendable {
        case file(URL)
        case data(Data)
    }

    let storage: Storage
    let name: String

    init(fileURL: URL) {
        storage = .file(fileURL)
        name = fileURL.lastPathComponent
    }

    init(data: Data, name: String) {
        storage = .data(data)
        self.name = name
    }
}

/// 图片预处理：最长边缩到 2048，转 JPEG 0.85，再传。
///
/// 全程只用 ImageIO / CoreGraphics（线程安全、不依赖 AppKit），所以可以在后台线程跑；
/// NSImage 只在主线程由缩略图 JPEG 建出来。
enum ImageProcessor {
    static let maxEdge: CGFloat = 2048
    static let jpegQuality: CGFloat = 0.85
    /// 服务端上限 20MB，压完远低于这个数；这里只是兜底。
    static let maxByteCount = 20 * 1024 * 1024
    private static let thumbnailEdge = 320

    private static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "tif", "tiff", "gif", "bmp"
    ]

    static func isSupportedImage(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func prepare(_ source: ImageSource) -> PreparedImage? {
        switch source.storage {
        case .file(let url):
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
            return prepare(data: data, name: source.name)
        case .data(let data):
            return prepare(data: data, name: source.name)
        }
    }

    static func prepare(data: Data, name: String) -> PreparedImage? {
        guard !data.isEmpty,
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(imageSource) > 0
        else { return nil }

        // 取原图尺寸，保证「只缩不放」：小图不会被放大到 2048。
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        let pixelWidth = properties?[kCGImagePropertyPixelWidth] as? Int ?? Int(maxEdge)
        let pixelHeight = properties?[kCGImagePropertyPixelHeight] as? Int ?? Int(maxEdge)
        let maxPixel = max(1, min(Int(maxEdge), max(pixelWidth, pixelHeight)))

        // WithTransform 会按 EXIF 方向把图转正。
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }

        // 透明底（截图带 alpha 时）铺白，否则 JPEG 会把透明画成黑块。
        let flattened = flattenOnWhite(scaled) ?? scaled
        guard let jpeg = encodeJPEG(flattened, quality: jpegQuality), jpeg.count <= maxByteCount else {
            return nil
        }

        let thumbCG = downscale(flattened, maxPixel: thumbnailEdge) ?? flattened
        guard let thumbJPEG = encodeJPEG(thumbCG, quality: 0.8) else { return nil }

        return PreparedImage(
            jpeg: jpeg,
            thumbnailJPEG: thumbJPEG,
            pixelSize: CGSize(width: flattened.width, height: flattened.height),
            name: name
        )
    }

    // MARK: - CoreGraphics

    private static func flattenOnWhite(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func downscale(_ image: CGImage, maxPixel: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxPixel else { return image }

        let scale = CGFloat(maxPixel) / CGFloat(longest)
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func encodeJPEG(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
