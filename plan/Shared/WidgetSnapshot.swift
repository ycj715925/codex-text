import Foundation

struct WidgetTaskSnapshot: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let timeText: String
    let isCompleted: Bool
    let priorityRaw: String?

    var priority: TaskPriority {
        TaskPriority(rawValue: priorityRaw ?? "") ?? .b
    }
}

struct WidgetDailyProgressSnapshot: Identifiable, Hashable, Codable {
    let day: Date
    let completedCount: Int
    let totalCount: Int
    let focusMinutes: Int

    var id: Date { day }

    var completionRatio: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
}

struct PlanWidgetSnapshot: Hashable, Codable {
    let date: Date
    let tasks: [WidgetTaskSnapshot]
    let completedCount: Int
    let totalCount: Int
    let isFocusing: Bool
    let focusTitle: String?
    let progressDays: [WidgetDailyProgressSnapshot]

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var progressText: String {
        "\(completedCount)/\(totalCount)"
    }

    init(
        date: Date,
        tasks: [WidgetTaskSnapshot],
        completedCount: Int,
        totalCount: Int,
        isFocusing: Bool = false,
        focusTitle: String? = nil,
        progressDays: [WidgetDailyProgressSnapshot] = []
    ) {
        self.date = date
        self.tasks = tasks
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.isFocusing = isFocusing
        self.focusTitle = focusTitle
        self.progressDays = progressDays
    }

    enum CodingKeys: String, CodingKey {
        case date
        case tasks
        case completedCount
        case totalCount
        case isFocusing
        case focusTitle
        case progressDays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        tasks = try container.decode([WidgetTaskSnapshot].self, forKey: .tasks)
        completedCount = try container.decode(Int.self, forKey: .completedCount)
        totalCount = try container.decode(Int.self, forKey: .totalCount)
        isFocusing = try container.decodeIfPresent(Bool.self, forKey: .isFocusing) ?? false
        focusTitle = try container.decodeIfPresent(String.self, forKey: .focusTitle)
        progressDays = try container.decodeIfPresent([WidgetDailyProgressSnapshot].self, forKey: .progressDays) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(completedCount, forKey: .completedCount)
        try container.encode(totalCount, forKey: .totalCount)
        try container.encode(isFocusing, forKey: .isFocusing)
        try container.encodeIfPresent(focusTitle, forKey: .focusTitle)
        try container.encode(progressDays, forKey: .progressDays)
    }

    static let empty = PlanWidgetSnapshot(date: Date(), tasks: [], completedCount: 0, totalCount: 0)
}

enum WidgetSnapshotStore {
    static let appGroupID = AppConstants.appGroupID
    static let fileName = "TodayWidgetSnapshot.json"

    static func read() -> PlanWidgetSnapshot {
        guard let data = try? Data(contentsOf: snapshotURL()),
              let snapshot = try? JSONDecoder().decode(PlanWidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func write(_ snapshot: PlanWidgetSnapshot) {
        let url = snapshotURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func snapshotURL() -> URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url.appendingPathComponent(fileName)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlanApp", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
