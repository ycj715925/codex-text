import Foundation
import SwiftUI
import WidgetKit

enum PlanTab: Hashable {
    case today
    case plan
}

@MainActor
final class PlanStore: ObservableObject {
    @Published var selectedTab: PlanTab = .today
    @Published var todayTasks: [PlanTask] = []
    @Published var plannedTasks: [PlanTask] = []
    @Published var templates: [PlanTemplate] = []
    @Published var selectedDate = Date()
    @Published var streak = 0
    @Published var activeFocusSession: FocusSession?
    @Published var progressSummaries: [DailyProgressSummary] = []
    @Published var recentFocusSessions: [FocusSession] = []
    @Published var upcomingTasks: [PlanTask] = []
    @Published var usageDayCount = 0
    @Published var focusFeedback: String?
    @Published var isShowingEditor = false
    @Published var editingTask: PlanTask?
    @Published var celebrate = false

    private let repository: PlanRepository
    private var feedbackToken = UUID()

    init(repository: PlanRepository = .shared) {
        self.repository = repository
    }

    func bootstrap() async {
        await repository.generateTasksFromTemplates()
        await repository.syncNotifications()
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refresh() {
        repository.expireStaleFocusSessions()
        todayTasks = repository.tasks(on: Date())
        plannedTasks = repository.tasks(on: selectedDate)
        templates = repository.templates()
        streak = repository.streakEndingToday()
        activeFocusSession = repository.activeFocusSession()
        progressSummaries = repository.progressSummaries(days: 7)
        recentFocusSessions = repository.recentFocusSessions(days: 7)
        upcomingTasks = repository.upcomingTasks(days: 7)
        usageDayCount = repository.usageDayCount()
        repository.writeWidgetSnapshot()
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        plannedTasks = repository.tasks(on: date)
    }

    func showQuickAdd() {
        selectedTab = .today
        editingTask = nil
        isShowingEditor = true
    }

    func handleDeepLink(_ url: URL) {
        switch url.host ?? url.pathComponents.dropFirst().first {
        case "add":
            showQuickAdd()
        case "plan":
            selectedTab = .plan
            isShowingEditor = false
        default:
            selectedTab = .today
            isShowingEditor = false
        }
    }

    func edit(_ task: PlanTask) {
        editingTask = task
        isShowingEditor = true
    }

    func saveTask(task: PlanTask?, title: String, dueDate: Date, reminderDate: Date?, notes: String, priority: TaskPriority, attachmentURLs: [URL]) async {
        if let task {
            await repository.updateTask(task, title: title, dueDate: dueDate, reminderDate: reminderDate, notes: notes, priority: priority, attachmentURLs: attachmentURLs)
        } else {
            await repository.createTask(title: title, dueDate: dueDate, reminderDate: reminderDate, notes: notes, priority: priority, attachmentURLs: attachmentURLs)
        }
        isShowingEditor = false
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func toggle(_ task: PlanTask) async {
        await repository.toggleTask(id: task.id)
        celebrate = task.isCompleted
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
        if celebrate {
            try? await Task.sleep(for: .seconds(1))
            celebrate = false
        }
    }

    func snooze(_ task: PlanTask, minutes: Int = 30) async {
        let reminderDate = await repository.snoozeTask(id: task.id, minutes: minutes)
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
        if let reminderDate {
            await showFeedback("已稍后到 \(reminderDate.formatted(date: .omitted, time: .shortened))")
        }
    }

    func snoozeUntilTonight(_ task: PlanTask) async {
        let reminderDate = await repository.snoozeTaskUntilTonight(id: task.id)
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
        if let reminderDate {
            await showFeedback("已稍后到 \(reminderDate.formatted(date: .omitted, time: .shortened))")
        }
    }

    func nowTasks(now: Date = Date()) -> [PlanTask] {
        repository.nowTasks(on: Date(), now: now)
    }

    func snoozedTasks(now: Date = Date()) -> [PlanTask] {
        repository.snoozedTasks(on: Date(), now: now)
    }

    func completedTasks() -> [PlanTask] {
        repository.completedTasks(on: Date())
    }

    func focusCandidate(now: Date = Date()) -> PlanTask? {
        repository.focusCandidate(on: Date(), now: now)
    }

    func isUsingSnoozedFallback(now: Date = Date()) -> Bool {
        nowTasks(now: now).isEmpty && !snoozedTasks(now: now).isEmpty
    }

    func taskForActiveFocus() -> PlanTask? {
        guard let activeFocusSession else { return nil }
        return repository.task(id: activeFocusSession.taskID)
    }

    func startFocus(task: PlanTask, minutes: Int) async {
        activeFocusSession = await repository.startFocus(taskID: task.id, minutes: minutes)
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
        await showFeedback("已开始 \(minutes) 分钟专注")
    }

    func completeFocus() async {
        guard let activeFocusSession else { return }
        repository.completeFocusSession(id: activeFocusSession.id)
        let minutes = repository.focusSession(id: activeFocusSession.id)?.effectiveMinutes ?? 0
        focusFeedback = "专注 +\(minutes) 分钟"
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
        try? await Task.sleep(for: .seconds(1))
        focusFeedback = nil
    }

    func abandonFocus() {
        guard let activeFocusSession else { return }
        repository.abandonFocusSession(id: activeFocusSession.id)
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func expireFocusIfNeeded() {
        repository.expireStaleFocusSessions()
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func delete(_ task: PlanTask) {
        repository.deleteTask(id: task.id)
        isShowingEditor = false
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func createTemplate(title: String, cadence: RepeatCadence, weekdays: [Int], monthDay: Int, hour: Int, minute: Int) async {
        repository.createTemplate(title: title, cadence: cadence, weekdays: weekdays, monthDay: monthDay, hour: hour, minute: minute)
        await repository.generateTasksFromTemplates()
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setTemplateEnabled(_ template: PlanTemplate, isEnabled: Bool) async {
        await repository.setTemplateEnabled(id: template.id, isEnabled: isEnabled)
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func deleteTemplate(_ template: PlanTemplate) {
        repository.deleteTemplate(id: template.id)
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func attachmentURL(for attachment: Attachment) -> URL {
        repository.attachmentURL(for: attachment)
    }

    func deleteAttachment(_ attachment: Attachment, from task: PlanTask) {
        repository.deleteAttachment(attachment, from: task)
        refresh()
    }

    private func showFeedback(_ message: String) async {
        let token = UUID()
        feedbackToken = token
        focusFeedback = message
        try? await Task.sleep(for: .seconds(1.2))
        if feedbackToken == token {
            focusFeedback = nil
        }
    }
}
