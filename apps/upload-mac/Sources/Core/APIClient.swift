import Foundation

/// 只做两件事：POST /api/ingest、GET /api/health。
/// 不轮询、不查批次列表——上传端提交即走（docs/05-协议.md §5）。
struct APIClient {
    let baseURL: URL

    static let defaultBase = "http://192.168.2.196:18086"
    /// 上传端铁律：请求超时 30s，超时按失败处理。
    static let ingestTimeout: TimeInterval = 30

    /// 健康检查只是给窗口顶部的黄条用，不需要等太久。
    private static let healthTimeout: TimeInterval = 6

    /// 单例 session：ephemeral（不落缓存，图片不进磁盘）、不等待网络（连不上要立刻报错，别让按钮转 30 秒）。
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = APIClient.ingestTimeout
        config.timeoutIntervalForResource = APIClient.ingestTimeout
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    // MARK: - 地址

    /// 把用户填的地址收拾成可用的 base URL。
    /// 允许只填 `192.168.1.8:8080`，自动补 http://；去掉结尾的斜杠。
    static func normalizedBase(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    // MARK: - 健康检查

    func health() async throws -> HealthResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("api").appendingPathComponent("health"))
        request.httpMethod = "GET"
        request.timeoutInterval = Self.healthTimeout

        let (data, response) = try await Self.send(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw IngestError.server(
                status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                code: envelope?.error.code,
                message: envelope?.error.message
            )
        }
        guard let decoded = try? JSONDecoder().decode(HealthResponse.self, from: data) else {
            throw IngestError.malformed
        }
        return decoded
    }

    // MARK: - 上传

    /// 多图 multipart。字段名按 openapi.yaml：`files`（可重复）、`note`、`date`。
    func ingest(images: [Data], note: String, date: String) async throws -> IngestResponse {
        guard !images.isEmpty else { throw IngestError.malformed }
        let boundary = "tianzige-\(UUID().uuidString)"

        var request = URLRequest(url: baseURL.appendingPathComponent("api").appendingPathComponent("ingest"))
        request.httpMethod = "POST"
        request.timeoutInterval = Self.ingestTimeout
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(boundary: boundary, images: images, note: note, date: date)

        let (data, response) = try await Self.send(request)
        guard let http = response as? HTTPURLResponse else { throw IngestError.malformed }

        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw IngestError.server(
                status: http.statusCode,
                code: envelope?.error.code,
                message: envelope?.error.message
            )
        }
        guard !data.isEmpty, let decoded = try? JSONDecoder().decode(IngestResponse.self, from: data) else {
            throw IngestError.malformed
        }
        return decoded
    }

    // MARK: - 底层

    private static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw IngestError.timeout
            case .cancelled:
                throw IngestError.offline
            default:
                // cannotConnectToHost / cannotFindHost / notConnectedToInternet / dnsLookupFailed …
                // 对用户都是同一句话：连不上。
                throw IngestError.offline
            }
        } catch {
            throw IngestError.offline
        }
    }

    private static func multipartBody(boundary: String, images: [Data], note: String, date: String) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }

        // 图片全部在本地转成 JPEG，所以这里固定 image/jpeg、.jpg 文件名。
        for (index, image) in images.enumerated() {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"files\"; filename=\"photo-\(index + 1).jpg\"\r\n")
            append("Content-Type: image/jpeg\r\n\r\n")
            body.append(image)
            append("\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"date\"\r\n\r\n")
        append(date)
        append("\r\n")

        if !note.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"note\"\r\n\r\n")
            append(note)
            append("\r\n")
        }

        append("--\(boundary)--\r\n")
        return body
    }
}
