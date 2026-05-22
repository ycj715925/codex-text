import Foundation
import SwiftData

enum RepeatCadence: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        }
    }
}

enum TaskPriority: String, Codable, CaseIterable, Identifiable {
    case s = "S"
    case a = "A"
    case b = "B"
    case c = "C"

    var id: String { rawValue }

    var sortRank: Int {
        switch self {
        case .s: return 0
        case .a: return 1
        case .b: return 2
        case .c: return 3
        }
    }
}

enum FocusSessionStatus: String, Codable, CaseIterable, Identifiable {
    case inProgress
    case completed
    case abandoned
    case timedOut

    var id: String { rawValue }
}

struct DailyProgressSummary: Identifiable, Hashable {
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

@Model
final class PlanTask: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var dueDate: Date
    var reminderDate: Date?
    var isCompleted: Bool
    var completedAt: Date?
    var notes: String
    var priorityRaw: String?
    var snoozedUntil: Date?
    var templateID: UUID?
    var notificationID: String?
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var attachments: [Attachment]

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date,
        reminderDate: Date? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        notes: String = "",
        priority: TaskPriority = .b,
        snoozedUntil: Date? = nil,
        templateID: UUID? = nil,
        notificationID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        attachments: [Attachment] = []
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.notes = notes
        self.priorityRaw = priority.rawValue
        self.snoozedUntil = snoozedUntil
        self.templateID = templateID
        self.notificationID = notificationID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attachments = attachments
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw ?? "") ?? .b }
        set { priorityRaw = newValue.rawValue }
    }
}

@Model
final class FocusSession: Identifiable {
    @Attribute(.unique) var id: UUID
    var taskID: UUID
    var taskTitle: String
    var startDate: Date
    var plannedMinutes: Int
    var actualMinutes: Int
    var effectiveMinutes: Int
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        taskID: UUID,
        taskTitle: String,
        startDate: Date = Date(),
        plannedMinutes: Int,
        actualMinutes: Int = 0,
        effectiveMinutes: Int = 0,
        status: FocusSessionStatus = .inProgress,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.startDate = startDate
        self.plannedMinutes = plannedMinutes
        self.actualMinutes = actualMinutes
        self.effectiveMinutes = effectiveMinutes
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var status: FocusSessionStatus {
        get { FocusSessionStatus(rawValue: statusRaw) ?? .inProgress }
        set { statusRaw = newValue.rawValue }
    }

    var plannedEndDate: Date {
        startDate.addingTimeInterval(TimeInterval(plannedMinutes * 60))
    }

    var timeoutDate: Date {
        startDate.addingTimeInterval(TimeInterval(plannedMinutes * 2 * 60))
    }

    func elapsedMinutes(at date: Date = Date()) -> Int {
        max(0, Int(date.timeIntervalSince(startDate) / 60))
    }

    func remainingSeconds(at date: Date = Date()) -> Int {
        max(0, Int(plannedEndDate.timeIntervalSince(date)))
    }

    func shouldTimeOut(at date: Date = Date()) -> Bool {
        status == .inProgress && date >= timeoutDate
    }
}

@Model
final class PlanTemplate: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var cadenceRaw: String
    var weekdays: [Int]
    var monthDay: Int
    var defaultReminderHour: Int
    var defaultReminderMinute: Int
    var isEnabled: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        cadence: RepeatCadence,
        weekdays: [Int] = [],
        monthDay: Int = 1,
        defaultReminderHour: Int = 9,
        defaultReminderMinute: Int = 0,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.cadenceRaw = cadence.rawValue
        self.weekdays = weekdays
        self.monthDay = monthDay
        self.defaultReminderHour = defaultReminderHour
        self.defaultReminderMinute = defaultReminderMinute
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    var cadence: RepeatCadence {
        get { RepeatCadence(rawValue: cadenceRaw) ?? .daily }
        set { cadenceRaw = newValue.rawValue }
    }
}

@Model
final class Attachment: Identifiable {
    @Attribute(.unique) var id: UUID
    var fileName: String
    var relativePath: String
    var taskID: UUID
    var createdAt: Date

    init(id: UUID = UUID(), fileName: String, relativePath: String, taskID: UUID, createdAt: Date = Date()) {
        self.id = id
        self.fileName = fileName
        self.relativePath = relativePath
        self.taskID = taskID
        self.createdAt = createdAt
    }
}

@Model
final class DailyStats: Identifiable {
    @Attribute(.unique) var id: UUID
    var day: Date
    var completedCount: Int
    var totalCount: Int
    var focusMinutes: Int
    var createdAt: Date

    init(id: UUID = UUID(), day: Date, completedCount: Int, totalCount: Int, focusMinutes: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.day = Calendar.current.startOfDay(for: day)
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.focusMinutes = focusMinutes
        self.createdAt = createdAt
    }
}
