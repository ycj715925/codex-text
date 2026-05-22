import Foundation
import SwiftData

@MainActor
final class PlanRepository {
    static let appGroupID = AppConstants.appGroupID
    static let shared = PlanRepository.makeShared()

    let container: ModelContainer
    let context: ModelContext
    private let writesWidgetSnapshot: Bool
    private let schedulesNotifications: Bool
    private let attachmentsDirectoryURL: URL

    init(inMemory: Bool = false) throws {
        let schema = Schema([PlanTask.self, PlanTemplate.self, Attachment.self, DailyStats.self, FocusSession.self])
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            attachmentsDirectoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("PlanTests-\(UUID().uuidString)", isDirectory: true)
        } else {
            configuration = ModelConfiguration(schema: schema, url: Self.storeURL())
            attachmentsDirectoryURL = Self.attachmentsDirectory()
        }
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        writesWidgetSnapshot = !inMemory
        schedulesNotifications = !inMemory
    }

    func tasks(on day: Date = Date()) -> [PlanTask] {
        let bounds = DateRules.dayBounds(for: day)
        let start = bounds.start
        let end = bounds.end
        let descriptor = FetchDescriptor<PlanTask>(
            predicate: #Predicate { $0.dueDate >= start && $0.dueDate < end },
            sortBy: [SortDescriptor(\.dueDate), SortDescriptor(\.createdAt)]
        )
        return sortedTasks(fetch(descriptor))
    }

    func tasks(from startDate: Date, days: Int) -> [PlanTask] {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let descriptor = FetchDescriptor<PlanTask>(
            predicate: #Predicate { $0.dueDate >= start && $0.dueDate < end },
            sortBy: [SortDescriptor(\.dueDate), SortDescriptor(\.createdAt)]
        )
        return sortedTasks(fetch(descriptor))
    }

    func task(id: UUID) -> PlanTask? {
        let descriptor = FetchDescriptor<PlanTask>(predicate: #Predicate { $0.id == id })
        return fetch(descriptor).first
    }

    func focusSession(id: UUID) -> FocusSession? {
        let descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == id })
        return fetch(descriptor).first
    }

    func activeFocusSession() -> FocusSession? {
        let activeStatus = FocusSessionStatus.inProgress.rawValue
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.statusRaw == activeStatus },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return fetch(descriptor).first
    }

    func template(id: UUID) -> PlanTemplate? {
        let descriptor = FetchDescriptor<PlanTemplate>(predicate: #Predicate { $0.id == id })
        return fetch(descriptor).first
    }

    func templates() -> [PlanTemplate] {
        let descriptor = FetchDescriptor<PlanTemplate>(sortBy: [SortDescriptor(\.createdAt)])
        return fetch(descriptor)
    }

    func createTask(title: String, dueDate: Date, reminderDate: Date?, notes: String, priority: TaskPriority, attachmentURLs: [URL]) async {
        let task = PlanTask(title: title, dueDate: dueDate, reminderDate: reminderDate, notes: notes, priority: priority)
        context.insert(task)
        copyAttachments(attachmentURLs, to: task)
        task.notificationID = await scheduleNotification(for: task)
        save()
    }

    func updateTask(_ task: PlanTask, title: String, dueDate: Date, reminderDate: Date?, notes: String, priority: TaskPriority, attachmentURLs: [URL]) async {
        task.title = title
        task.dueDate = dueDate
        task.reminderDate = reminderDate
        task.notes = notes
        task.priority = priority
        task.snoozedUntil = nil
        task.updatedAt = Date()
        copyAttachments(attachmentURLs, to: task)
        task.notificationID = await scheduleNotification(for: task)
        save()
    }

    func completeTask(id: UUID) async {
        guard let task = task(id: id) else { return }
        task.isCompleted = true
        task.completedAt = Date()
        task.snoozedUntil = nil
        task.updatedAt = Date()
        NotificationScheduler.shared.cancel(identifier: task.notificationID)
        task.notificationID = nil
        save()
    }

    func toggleTask(id: UUID) async {
        guard let task = task(id: id) else { return }
        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? Date() : nil
        if task.isCompleted {
            task.snoozedUntil = nil
        }
        task.updatedAt = Date()
        if task.isCompleted {
            NotificationScheduler.shared.cancel(identifier: task.notificationID)
            task.notificationID = nil
        } else {
            task.notificationID = await scheduleNotification(for: task)
        }
        save()
    }

    @discardableResult
    func snoozeTask(id: UUID, minutes: Int) async -> Date? {
        guard let task = task(id: id) else { return nil }
        let reminderDate = Date().addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        task.reminderDate = reminderDate
        task.snoozedUntil = reminderDate
        task.isCompleted = false
        task.completedAt = nil
        task.updatedAt = Date()
        task.notificationID = await scheduleNotification(for: task)
        save()
        return reminderDate
    }

    @discardableResult
    func snoozeTaskUntilTonight(id: UUID, now: Date = Date()) async -> Date? {
        let calendar = Calendar.current
        let tonight = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(30 * 60)
        let reminderDate = tonight > now ? tonight : now.addingTimeInterval(30 * 60)
        return await snoozeTask(id: id, until: reminderDate)
    }

    @discardableResult
    func snoozeTask(id: UUID, until reminderDate: Date) async -> Date? {
        guard let task = task(id: id) else { return nil }
        task.reminderDate = reminderDate
        task.snoozedUntil = reminderDate
        task.isCompleted = false
        task.completedAt = nil
        task.updatedAt = Date()
        task.notificationID = await scheduleNotification(for: task)
        save()
        return reminderDate
    }

    func focusCandidate(on day: Date = Date(), now: Date = Date()) -> PlanTask? {
        let available = tasks(on: day).filter { !$0.isCompleted && !isSnoozed($0, at: now) }
        if let first = available.first {
            return first
        }
        return snoozedTasks(on: day, now: now).first
    }

    func nowTasks(on day: Date = Date(), now: Date = Date()) -> [PlanTask] {
        tasks(on: day).filter { !$0.isCompleted && !isSnoozed($0, at: now) }
    }

    func snoozedTasks(on day: Date = Date(), now: Date = Date()) -> [PlanTask] {
        tasks(on: day)
            .filter { !$0.isCompleted && isSnoozed($0, at: now) }
            .sorted {
                ($0.snoozedUntil ?? .distantFuture) < ($1.snoozedUntil ?? .distantFuture)
            }
    }

    func completedTasks(on day: Date = Date()) -> [PlanTask] {
        tasks(on: day).filter(\.isCompleted)
    }

    func startFocus(taskID: UUID, minutes: Int, now: Date = Date()) async -> FocusSession? {
        expireStaleFocusSessions(now: now)
        if let active = activeFocusSession() {
            return active
        }
        guard let task = task(id: taskID) else { return nil }
        let session = FocusSession(
            taskID: task.id,
            taskTitle: task.title,
            startDate: now,
            plannedMinutes: min(max(minutes, 1), 180),
            createdAt: now,
            updatedAt: now
        )
        context.insert(session)
        save()
        await scheduleFocusEnd(for: session)
        return session
    }

    func completeFocusSession(id: UUID, now: Date = Date()) {
        guard let session = focusSession(id: id), session.status == .inProgress else { return }
        let actualMinutes = max(1, session.elapsedMinutes(at: now))
        session.status = .completed
        session.actualMinutes = actualMinutes
        session.effectiveMinutes = min(actualMinutes, session.plannedMinutes)
        session.updatedAt = now
        cancelFocusEnd(sessionID: session.id)
        save()
    }

    func abandonFocusSession(id: UUID, now: Date = Date()) {
        guard let session = focusSession(id: id), session.status == .inProgress else { return }
        session.status = .abandoned
        session.actualMinutes = session.elapsedMinutes(at: now)
        session.effectiveMinutes = 0
        session.updatedAt = now
        cancelFocusEnd(sessionID: session.id)
        save()
    }

    func expireStaleFocusSessions(now: Date = Date()) {
        let activeStatus = FocusSessionStatus.inProgress.rawValue
        let descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.statusRaw == activeStatus })
        let sessions = fetch(descriptor)
        var didChange = false
        for session in sessions where session.shouldTimeOut(at: now) {
            session.status = .timedOut
            session.actualMinutes = session.elapsedMinutes(at: now)
            session.effectiveMinutes = 0
            session.updatedAt = now
            cancelFocusEnd(sessionID: session.id)
            didChange = true
        }
        if didChange {
            save()
        }
    }

    func deleteTask(id: UUID) {
        guard let task = task(id: id) else { return }
        delete(task)
        save()
    }

    func createTemplate(title: String, cadence: RepeatCadence, weekdays: [Int], monthDay: Int, hour: Int, minute: Int) {
        context.insert(PlanTemplate(title: title, cadence: cadence, weekdays: weekdays, monthDay: monthDay, defaultReminderHour: hour, defaultReminderMinute: minute))
        save()
    }

    func setTemplateEnabled(id: UUID, isEnabled: Bool) async {
        guard let template = template(id: id) else { return }
        template.isEnabled = isEnabled
        if isEnabled {
            save()
            await generateTasksFromTemplates()
        } else {
            removeFutureGeneratedTasks(templateID: id)
            save()
        }
    }

    func deleteTemplate(id: UUID) {
        guard let template = template(id: id) else { return }
        removeFutureGeneratedTasks(templateID: id)
        context.delete(template)
        save()
    }

    private func delete(_ task: PlanTask) {
        NotificationScheduler.shared.cancel(identifier: task.notificationID)
        for attachment in task.attachments {
            try? FileManager.default.removeItem(at: attachmentURL(for: attachment))
        }
        context.delete(task)
    }

    func deleteAttachment(_ attachment: Attachment, from task: PlanTask) {
        try? FileManager.default.removeItem(at: attachmentURL(for: attachment))
        task.attachments.removeAll { $0.id == attachment.id }
        context.delete(attachment)
        task.updatedAt = Date()
        save()
    }

    private func scheduleNotification(for task: PlanTask) async -> String? {
        guard schedulesNotifications else { return task.notificationID }
        return await NotificationScheduler.shared.schedule(task: task)
    }

    private func scheduleFocusEnd(for session: FocusSession) async {
        guard schedulesNotifications else { return }
        await NotificationScheduler.shared.scheduleFocusEnd(session: session)
    }

    private func cancelFocusEnd(sessionID: UUID) {
        guard schedulesNotifications else { return }
        NotificationScheduler.shared.cancelFocus(sessionID: sessionID)
    }

    func generateTasksFromTemplates(horizonDays: Int = 60) async {
        let existing = tasks(from: Date(), days: horizonDays)
        for template in templates().filter(\.isEnabled) {
            let dates = DateRules.occurrenceDates(for: template, from: Date(), days: horizonDays)
            for day in dates where !hasExistingTask(templateID: template.id, day: day, in: existing) {
                let reminderDate = DateRules.reminderDate(for: day, template: template)
                let task = PlanTask(title: template.title, dueDate: reminderDate ?? day, reminderDate: reminderDate, templateID: template.id)
                context.insert(task)
                task.notificationID = await scheduleNotification(for: task)
            }
        }
        save()
    }

    func syncNotifications(horizonDays: Int = 60) async {
        guard schedulesNotifications else { return }
        await NotificationScheduler.shared.requestAuthorization()
        for task in tasks(from: Date(), days: horizonDays) {
            task.notificationID = await scheduleNotification(for: task)
        }
        save()
    }

    func progressText(for day: Date = Date()) -> String {
        let items = tasks(on: day)
        let completed = items.filter(\.isCompleted).count
        return "\(completed)/\(items.count)"
    }

    func progressSummaries(days: Int = 7, endingOn date: Date = Date()) -> [DailyProgressSummary] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: date)
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - days + 1, to: end) else { return nil }
            let items = tasks(on: day)
            return DailyProgressSummary(
                day: day,
                completedCount: items.filter(\.isCompleted).count,
                totalCount: items.count,
                focusMinutes: focusMinutes(on: day)
            )
        }
    }

    func recentFocusSessions(days: Int = 7, limit: Int = 8, endingOn date: Date = Date()) -> [FocusSession] {
        let calendar = Calendar.current
        let end = DateRules.dayBounds(for: date).end
        let startDay = calendar.date(byAdding: .day, value: -max(0, days - 1), to: calendar.startOfDay(for: date)) ?? date
        let activeStatus = FocusSessionStatus.inProgress.rawValue
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startDate >= startDay && $0.startDate < end && $0.statusRaw != activeStatus },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return Array(fetch(descriptor).prefix(limit))
    }

    func upcomingTasks(days: Int = 7, from date: Date = Date()) -> [PlanTask] {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        return tasks(from: tomorrow, days: days).filter { !$0.isCompleted }
    }

    func usageDayCount(endingOn date: Date = Date()) -> Int {
        let calendar = Calendar.current
        guard let first = firstActivityDate() else { return 0 }
        let firstDay = calendar.startOfDay(for: first)
        let endDay = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: firstDay, to: endDay).day ?? 0
        return max(1, days + 1)
    }

    func streakEndingToday() -> Int {
        var streak = 0
        var cursor = Calendar.current.startOfDay(for: Date())
        for _ in 0..<AppConstants.maxStreakDays {
            let items = tasks(on: cursor)
            guard !items.isEmpty, items.allSatisfy(\.isCompleted) else { break }
            streak += 1
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    func attachmentURL(for attachment: Attachment) -> URL {
        attachmentsDirectoryURL.appendingPathComponent(attachment.relativePath)
    }

    func save() {
        updateDailyStats(for: Date())
        do {
            try context.save()
        } catch {
            #if DEBUG
            assertionFailure("PlanRepository.save() failed: \(error)")
            #endif
        }
        if writesWidgetSnapshot {
            writeWidgetSnapshot()
        }
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            #if DEBUG
            print("[PlanRepository] fetch failed: \(error)")
            #endif
            return []
        }
    }

    func writeWidgetSnapshot(for day: Date = Date()) {
        let items = tasks(on: day)
        let now = Date()
        let focus = activeFocusSession()
        let candidate = focusCandidate(on: day, now: now)
        let visibleTasks = widgetVisibleTasks(items: items, candidate: candidate, now: now)
        let snapshot = PlanWidgetSnapshot(
            date: Date(),
            tasks: visibleTasks.prefix(4).map {
                WidgetTaskSnapshot(
                    id: $0.id,
                    title: $0.title,
                    timeText: $0.reminderDate?.formatted(date: .omitted, time: .shortened) ?? "",
                    isCompleted: $0.isCompleted,
                    priorityRaw: $0.priority.rawValue
                )
            },
            completedCount: items.filter(\.isCompleted).count,
            totalCount: items.count,
            isFocusing: focus != nil,
            focusTitle: focus?.taskTitle,
            progressDays: progressSummaries(days: 7, endingOn: day).map {
                WidgetDailyProgressSnapshot(
                    day: $0.day,
                    completedCount: $0.completedCount,
                    totalCount: $0.totalCount,
                    focusMinutes: $0.focusMinutes
                )
            }
        )
        WidgetSnapshotStore.write(snapshot)
    }

    private func sortedTasks(_ tasks: [PlanTask]) -> [PlanTask] {
        tasks.sorted {
            if $0.isCompleted != $1.isCompleted {
                return !$0.isCompleted
            }
            if $0.priority.sortRank != $1.priority.sortRank {
                return $0.priority.sortRank < $1.priority.sortRank
            }
            if $0.dueDate != $1.dueDate {
                return $0.dueDate < $1.dueDate
            }
            return $0.createdAt < $1.createdAt
        }
    }

    private func widgetVisibleTasks(items: [PlanTask], candidate: PlanTask?, now: Date) -> [PlanTask] {
        var result: [PlanTask] = []
        if let candidate {
            result.append(candidate)
        }
        let importantSnoozed = items.filter {
            !$0.isCompleted && isSnoozed($0, at: now) && ($0.priority == .s || $0.priority == .a)
        }
        for task in importantSnoozed + items where !result.contains(where: { $0.id == task.id }) {
            result.append(task)
        }
        return result
    }

    private func isSnoozed(_ task: PlanTask, at date: Date) -> Bool {
        guard let snoozedUntil = task.snoozedUntil else { return false }
        return snoozedUntil > date
    }

    private func focusMinutes(on day: Date) -> Int {
        let bounds = DateRules.dayBounds(for: day)
        let start = bounds.start
        let end = bounds.end
        let completed = FocusSessionStatus.completed.rawValue
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startDate >= start && $0.startDate < end && $0.statusRaw == completed }
        )
        return fetch(descriptor).reduce(0) { $0 + $1.effectiveMinutes }
    }

    private func firstActivityDate() -> Date? {
        let taskDescriptor = FetchDescriptor<PlanTask>(sortBy: [SortDescriptor(\.createdAt)])
        let sessionDescriptor = FetchDescriptor<FocusSession>(sortBy: [SortDescriptor(\.startDate)])
        let firstTask = fetch(taskDescriptor).first?.createdAt
        let firstSession = fetch(sessionDescriptor).first?.startDate
        switch (firstTask, firstSession) {
        case (.some(let taskDate), .some(let sessionDate)):
            return min(taskDate, sessionDate)
        case (.some(let taskDate), .none):
            return taskDate
        case (.none, .some(let sessionDate)):
            return sessionDate
        case (.none, .none):
            return nil
        }
    }

    private func updateDailyStats(for day: Date) {
        let bounds = DateRules.dayBounds(for: day)
        let start = bounds.start
        let items = tasks(on: day)
        let descriptor = FetchDescriptor<DailyStats>(predicate: #Predicate { $0.day == start })
        let stats = fetch(descriptor).first ?? DailyStats(day: start, completedCount: 0, totalCount: 0)
        if stats.modelContext == nil {
            context.insert(stats)
        }
        stats.completedCount = items.filter(\.isCompleted).count
        stats.totalCount = items.count
        stats.focusMinutes = focusMinutes(on: day)
    }

    private func hasExistingTask(templateID: UUID, day: Date, in tasks: [PlanTask]) -> Bool {
        let bounds = DateRules.dayBounds(for: day)
        return tasks.contains { $0.templateID == templateID && $0.dueDate >= bounds.start && $0.dueDate < bounds.end }
    }

    private func removeFutureGeneratedTasks(templateID: UUID) {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        for task in tasks(from: tomorrow, days: AppConstants.taskHorizonDays) where task.templateID == templateID && !task.isCompleted {
            delete(task)
        }
    }

    private func copyAttachments(_ urls: [URL], to task: PlanTask) {
        let directory = attachmentsDirectoryURL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for url in urls {
            let ext = url.pathExtension.isEmpty ? "image" : url.pathExtension
            let fileName = "\(UUID().uuidString).\(ext)"
            let destination = directory.appendingPathComponent(fileName)
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess { url.stopAccessingSecurityScopedResource() }
            }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: url, to: destination)
                task.attachments.append(Attachment(fileName: url.lastPathComponent, relativePath: fileName, taskID: task.id))
            } catch {
                continue
            }
        }
    }

    private static func makeShared() -> PlanRepository {
        do {
            return try PlanRepository()
        } catch {
            fatalError("Failed to create PlanRepository: \(error)")
        }
    }

    private static func baseDirectory() -> URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlanApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    private static func storeURL() -> URL {
        baseDirectory().appendingPathComponent("PlanApp.store")
    }

    private static func attachmentsDirectory() -> URL {
        baseDirectory().appendingPathComponent("Attachments", isDirectory: true)
    }
}
