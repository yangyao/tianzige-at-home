import UIKit

/// 已经压缩好的待上传图片。只留 JPEG 数据和小缩略图，不持有原图，省内存。
struct SelectedImage: Identifiable {
    let id = UUID()
    /// 压缩后 JPEG（最长边 2048 / 质量 0.85），直接作为 multipart 文件体。
    let jpegData: Data
    /// 缩略条里展示用的小图，避免每帧解码大图。
    let thumbnail: UIImage
    let filename: String
}

/// 上传时交给 APIClient 的最小载荷。
struct UploadFile {
    let data: Data
    let filename: String
    let mimeType: String
}
