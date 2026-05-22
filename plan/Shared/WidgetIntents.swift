import AppIntents
import Foundation
import WidgetKit

struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "完成任务"
    static let description = IntentDescription("从桌面小组件直接完成计划任务。")

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}

    init(taskID: String) {
        self.taskID = taskID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        await PlanRepository.shared.completeTask(id: id)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct SnoozeTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "稍后提醒"
    static let description = IntentDescription("把计划任务延期到稍后。")

    @Parameter(title: "Task ID")
    var taskID: String

    @Parameter(title: "Minutes")
    var minutes: Int

    init() {}

    init(taskID: String, minutes: Int = 30) {
        self.taskID = taskID
        self.minutes = minutes
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        await PlanRepository.shared.snoozeTask(id: id, minutes: minutes)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
