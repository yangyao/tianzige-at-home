import Foundation

/// 手写 multipart/form-data。字段名与 `apps/upload-web/upload.html` 一致：
/// `files[]`（可重复）、`note`、`date`，对应 openapi.yaml 里的 files / note / date。
struct MultipartBody {
    let boundary: String
    private(set) var data = Data()

    init(boundary: String = "Tianzige-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    mutating func appendFile(_ file: UploadFile, fieldName: String) {
        appendText("--\(boundary)\r\n")
        appendText("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(file.filename)\"\r\n")
        appendText("Content-Type: \(file.mimeType)\r\n\r\n")
        data.append(file.data)
        appendText("\r\n")
    }

    mutating func appendField(_ name: String, value: String) {
        appendText("--\(boundary)\r\n")
        appendText("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendText("\(value)\r\n")
    }

    mutating func finalize() {
        appendText("--\(boundary)--\r\n")
    }

    private mutating func appendText(_ string: String) {
        data.append(Data(string.utf8))
    }
}
