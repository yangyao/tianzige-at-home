import Foundation

/// 只封装上传端用得到的两个接口：
/// - `POST /api/ingest`（spec: operationId ingest）
/// - `GET  /api/health`（spec: operationId getHealth）
/// 不做 batches / day / img，那些是 Web 与电视端的事。
struct APIClient {
    let baseURL: URL

    /// 上传请求 30s 超时（upload-ui.md §3 铁律 3）。超时按失败处理，图片保留可重试。
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: configuration)
    }()

    // MARK: - GET /api/health

    func health() async throws -> HealthResponse {
        var request = URLRequest(url: url(path: "api/health"))
        request.httpMethod = "GET"
        // 连通性测试要快，不能让人在设置页干等 30 秒
        request.timeoutInterval = 8

        let (data, response) = try await send(request)
        try Self.ensureSuccess(data: data, response: response)

        do {
            return try JSONDecoder().decode(HealthResponse.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    // MARK: - POST /api/ingest

    func ingest(files: [UploadFile], note: String, date: String) async throws -> IngestResponse {
        var body = MultipartBody()
        for file in files {
            body.appendFile(file, fieldName: "files[]")
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            body.appendField("note", value: trimmedNote)
        }
        body.appendField("date", value: date)
        body.finalize()

        var request = URLRequest(url: url(path: "api/ingest"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("multipart/form-data; boundary=\(body.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data

        let (data, response) = try await send(request)
        try Self.ensureSuccess(data: data, response: response)

        do {
            return try JSONDecoder().decode(IngestResponse.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    // MARK: - 公共

    private func url(path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await Self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.decoding
            }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            if error.code == .timedOut {
                throw APIError.timeout
            }
            throw APIError.network(error.localizedDescription)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    /// 202 / 200 之外的响应，优先取服务端给的中文 message。
    private static func ensureSuccess(data: Data, response: HTTPURLResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            if let payload = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw APIError.server(code: payload.error.code, message: payload.error.message)
            }
            throw APIError.unexpectedStatus(response.statusCode)
        }
    }
}
