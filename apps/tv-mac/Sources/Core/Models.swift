import Foundation

// 与 spec/openapi.yaml 对齐的数据模型。解析原则（协议 §5.1）：
// 字段缺失、类型对不上都不能崩，缺了就走默认值，三态兜底在 DayLogic 里做。

struct DayView: Codable, Equatable {
    var date: String = ""
    var isToday: Bool = false
    var daysAgo: Int = 0
    var state: String = "empty"
    var note: String?
    var images: [ImageRef] = []
    var subjects: [SubjectGroup] = []
    var batchIds: [Int64] = []

    enum CodingKeys: String, CodingKey {
        case date, isToday = "is_today", daysAgo = "days_ago", state, note
        case images, subjects, batchIds = "batch_ids"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        isToday = try c.decodeIfPresent(Bool.self, forKey: .isToday) ?? false
        daysAgo = try c.decodeIfPresent(Int.self, forKey: .daysAgo) ?? 0
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "empty"
        note = try c.decodeIfPresent(String.self, forKey: .note)
        images = try c.decodeIfPresent([ImageRef].self, forKey: .images) ?? []
        subjects = try c.decodeIfPresent([SubjectGroup].self, forKey: .subjects) ?? []
        batchIds = try c.decodeIfPresent([Int64].self, forKey: .batchIds) ?? []
    }
}

struct ImageRef: Codable, Equatable {
    var id: Int64 = 0
    var url: String = ""
    var width: Int = 0
    var height: Int = 0

    enum CodingKeys: String, CodingKey { case id, url, width, height }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? 0
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 0
    }
}

struct SubjectGroup: Codable, Equatable {
    var subject: String = ""
    var items: [HomeworkItem] = []
    var imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case subject, items, imageUrl = "image_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
        items = try c.decodeIfPresent([HomeworkItem].self, forKey: .items) ?? []
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
    }
}

struct HomeworkItem: Codable, Equatable {
    var id: Int64 = 0
    var content: String = ""
    var done: Bool = false

    enum CodingKeys: String, CodingKey { case id, content, done }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? 0
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
    }
}

/// 日期条圆点用：date(YYYY-MM-DD) -> 有没有作业。
struct DayMark: Codable, Equatable {
    var date: String = ""
    var has: Bool = false
    var itemCount: Int = 0

    enum CodingKeys: String, CodingKey {
        case date, has, itemCount = "item_count"
    }

    init(date: String, has: Bool, itemCount: Int) {
        self.date = date
        self.has = has
        self.itemCount = itemCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        has = try c.decodeIfPresent(Bool.self, forKey: .has) ?? false
        itemCount = try c.decodeIfPresent(Int.self, forKey: .itemCount) ?? 0
    }
}

struct HealthResponse: Codable {
    var ok: Bool = false
    var version: String?

    enum CodingKeys: String, CodingKey { case ok, version }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        version = try c.decodeIfPresent(String.self, forKey: .version)
    }
}

/// 磁盘缓存的一条：数据 + 存的时间（epoch 秒，顶栏「上次更新 HH:mm」用）。
struct CachedDay: Codable, Equatable {
    var day: DayView
    var savedAt: TimeInterval
}
