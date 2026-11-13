import Foundation

/// 只读的三个接口：/api/day、/api/days、/api/health。
/// 呈现端不上传、不重跑、不删除——那是上传端和 Web 调试页的事。
struct TvApi {

    private var session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
    }

    func getDay(base: String, date: Date) async throws -> DayView {
        try await get(base: base, path: "api/day", query: ["date": DayLogic.format(date)])
    }

    /// 日期条圆点：一次取一周。
    func getDays(base: String, from: Date, to: Date) async throws -> [DayMark] {
        struct Wrapper: Decodable { var days: [DayMark] = [] }
        let wrapper: Wrapper = try await get(
            base: base, path: "api/days",
            query: ["from": DayLogic.format(from), "to": DayLogic.format(to)]
        )
        return wrapper.days
    }

    func health(base: String) async throws -> HealthResponse {
        let result: HealthResponse = try await get(base: base, path: "api/health", query: [:])
        guard result.ok else { throw URLError(.cannotConnectToHost) }
        return result
    }

    private func get<Response: Decodable>(base: String, path: String, query: [String: String]) async throws -> Response {
        guard
            var components = URLComponents(string: base.trimmingCharacters(in: .whitespacesAndNewlines))
        else { throw URLError(.badURL) }
        components.path = (components.path.isEmpty ? "" : components.path)
            + "/" + path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.cannotConnectToHost)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
