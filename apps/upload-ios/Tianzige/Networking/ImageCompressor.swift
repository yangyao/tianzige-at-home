import UIKit

/// 压缩产物。全部是值类型，可以安全地从后台线程送回主线程。
struct CompressedImage: Sendable {
    let jpegData: Data
    let thumbnailData: Data
    let pixelWidth: Int
    let pixelHeight: Int
}

/// 上传前统一压一遍：最长边 2048、JPEG 0.85。
/// HEIC 也走 `UIImage` → `jpegData`，落地就是 JPEG，服务端最稳；
/// 而且原图动辄 5–10MB，3 米外看电视根本看不出 2048 和 4032 的区别，没必要传。
enum ImageCompressor {
    static let maxPixelSize: CGFloat = 2048
    static let jpegQuality: CGFloat = 0.85
    static let thumbnailPixelSize: CGFloat = 240

    static func compress(_ data: Data) -> CompressedImage? {
        guard let source = UIImage(data: data) else { return nil }

        let downscaled = resize(source, maxPixelSize: maxPixelSize)
        guard let jpeg = downscaled.jpegData(compressionQuality: jpegQuality) else { return nil }

        let thumbnail = resize(downscaled, maxPixelSize: thumbnailPixelSize)
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.7) else { return nil }

        let size = pixelSize(of: downscaled)
        return CompressedImage(
            jpegData: jpeg,
            thumbnailData: thumbnailData,
            pixelWidth: Int(size.width),
            pixelHeight: Int(size.height)
        )
    }

    static func pixelSize(of image: UIImage) -> CGSize {
        CGSize(
            width: (image.size.width * image.scale).rounded(),
            height: (image.size.height * image.scale).rounded()
        )
    }

    /// 等比缩到最长边 maxPixelSize 以内，输出按 1x 渲染，像素即尺寸。
    static func resize(_ image: UIImage, maxPixelSize: CGFloat) -> UIImage {
        let current = pixelSize(of: image)
        let longest = max(current.width, current.height)
        guard longest > maxPixelSize else { return image }

        let ratio = maxPixelSize / longest
        let target = CGSize(
            width: max(1, (current.width * ratio).rounded()),
            height: max(1, (current.height * ratio).rounded())
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
