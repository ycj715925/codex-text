import Foundation
import SwiftData
import XCTest

final class PlanCoreTests: XCTestCase {
    func testDailyTemplateGeneratesEveryDay() {
        let calendar = Calendar(identifier: .gregorian)
        let start = DateComponents(calendar: calendar, year: 2026, month: 5, day: 16).date!
        let template = PlanTemplate(title: "阅读", cadence: .daily)

        let dates = DateRules.occurrenceDates(for: template, from: start, days: 3, calendar: calendar)

        XCTAssertEqual(dates.count, 3)
        XCTAssertEqual(calendar.component(.day, from: dates[0]), 16)
        XCTAssertEqual(calendar.component(.day, from: dates[2]), 18)
    }

    func testWeeklyTemplateUsesSelectedWeekdays() {
        let calendar = Calendar(identifier: .gregorian)
        let start = DateComponents(calendar: calendar, year: 2026, month: 5, day: 18).date!
        let template = PlanTemplate(title: "运动", cadence: .weekly, weekdays: [2, 4])

        let dates = DateRules.occurrenceDates(for: template, from: start, days: 7, calendar: calendar)
        let weekdays = dates.map { calendar.component(.weekday, from: $0) }

        XCTAssertEqual(weekdays, [2, 4])
    }

    func testMonthlyTemplateFallsBackToLastDayOfShortMonth() {
        let calendar = Calendar(identifier: .gregorian)
        let start = DateComponents(calendar: calendar, year: 2026, month: 2, day: 1).date!
        let template = PlanTemplate(title: "月度复盘", cadence: .monthly, monthDay: 31)

        let dates = DateRules.occurrenceDates(for: template, from: start, days: 31, calendar: calendar)

        XCTAssertEqual(dates.count, 1)
        XCTAssertEqual(calendar.component(.day, from: dates[0]), 28)
    }

    @MainActor
    func testRepositoryToggleIsSharedStateForIntentStyleActions() async throws {
        let repository = try PlanRepository(inMemory: true)
        let task = PlanTask(title: "写计划", dueDate: Date())
        repository.context.insert(task)
        repository.save()

        await repository.completeTask(id: task.id)

        XCTAssertTrue(repository.task(id: task.id)?.isCompleted == true)
    }

    @MainActor
    func testAttachmentCopyStoresReferenceOnTask() async throws {
        let repository = try PlanRepository(inMemory: true)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("plan-test-image.txt")
        try "image".write(to: source, atomically: true, encoding: .utf8)

        await repository.createTask(title: "记录", dueDate: Date(), reminderDate: nil, notes: "", priority: .b, attachmentURLs: [source])

        let task = repository.tasks(on: Date()).first
        XCTAssertEqual(task?.attachments.count, 1)
        XCTAssertEqual(task?.attachments.first?.fileName, "plan-test-image.txt")
    }

    @MainActor
    func testTasksSortByCompletionThenPriority() throws {
        let repository = try PlanRepository(inMemory: true)
        let now = Date()
        let low = PlanTask(title: "普通", dueDate: now, priority: .c)
        let high = PlanTask(title: "最重要", dueDate: now, priority: .s)
        let completed = PlanTask(title: "已完成", dueDate: now, isCompleted: true, priority: .s)
        repository.context.insert(low)
        repository.context.insert(high)
        repository.context.insert(completed)
        repository.save()

        let tasks = repository.tasks(on: now)

        XCTAssertEqual(tasks.map(\.title), ["最重要", "普通", "已完成"])
    }

    @MainActor
    func testFocusCandidateUsesPriorityThenDueDateThenCreatedAt() throws {
        let repository = try PlanRepository(inMemory: true)
        let calendar = Calendar(identifier: .gregorian)
        let base = DateComponents(calendar: calendar, year: 2026, month: 5, day: 19, hour: 9).date!
        let earlyA = PlanTask(title: "A 早到期", dueDate: base, priority: .a, createdAt: base)
        let lateS = PlanTask(title: "S 晚到期", dueDate: base.addingTimeInterval(3600), priority: .s, createdAt: base.addingTimeInterval(10))
        let earlyS = PlanTask(title: "S 早到期", dueDate: base.addingTimeInterval(1800), priority: .s, createdAt: base.addingTimeInterval(20))
        repository.context.insert(earlyA)
        repository.context.insert(lateS)
        repository.context.insert(earlyS)
        repository.save()

        let candidate = repository.focusCandidate(on: base, now: base)

        XCTAssertEqual(candidate?.title, "S 早到期")
    }

    @MainActor
    func testSnoozedTaskReturnsToNowAfterSnoozeExpires() async throws {
        let repository = try PlanRepository(inMemory: true)
        let now = Date()
        let task = PlanTask(title: "先推进", dueDate: now, priority: .s)
        repository.context.insert(task)
        repository.save()

        await repository.snoozeTask(id: task.id, until: now.addingTimeInterval(15 * 60))

        XCTAssertTrue(repository.nowTasks(on: now, now: now).isEmpty)
        XCTAssertEqual(repository.snoozedTasks(on: now, now: now).map(\.id), [task.id])
        XCTAssertEqual(repository.nowTasks(on: now, now: now.addingTimeInterval(16 * 60)).map(\.id), [task.id])
    }

    @MainActor
    func testAllSnoozedTasksFallbackToSoonestSnoozedCandidate() async throws {
        let repository = try PlanRepository(inMemory: true)
        let now = Date()
        let later = PlanTask(title: "晚点", dueDate: now, priority: .s)
        let sooner = PlanTask(title: "快到期", dueDate: now, priority: .b)
        repository.context.insert(later)
        repository.context.insert(sooner)
        repository.save()

        await repository.snoozeTask(id: later.id, until: now.addingTimeInterval(30 * 60))
        await repository.snoozeTask(id: sooner.id, until: now.addingTimeInterval(15 * 60))

        XCTAssertEqual(repository.focusCandidate(on: now, now: now)?.title, "快到期")
    }

    @MainActor
    func testFocusSessionCompletionCountsEffectiveMinutesOnStartDay() async throws {
        let repository = try PlanRepository(inMemory: true)
        let calendar = Calendar(identifier: .gregorian)
        let start = DateComponents(calendar: calendar, year: 2026, month: 5, day: 19, hour: 23, minute: 55).date!
        let nextDay = DateComponents(calendar: calendar, year: 2026, month: 5, day: 20, hour: 0, minute: 5).date!
        let task = PlanTask(title: "跨天专注", dueDate: start)
        repository.context.insert(task)
        repository.save()

        let startedSession = await repository.startFocus(taskID: task.id, minutes: 15, now: start)
        let session = try XCTUnwrap(startedSession)
        repository.completeFocusSession(id: session.id, now: nextDay)

        XCTAssertEqual(repository.focusSession(id: session.id)?.status, .completed)
        XCTAssertEqual(repository.progressSummaries(days: 1, endingOn: start).first?.focusMinutes, 10)
        XCTAssertEqual(repository.progressSummaries(days: 1, endingOn: nextDay).first?.focusMinutes, 0)
    }

    @MainActor
    func testTimedOutFocusSessionDoesNotCountEffectiveMinutes() async throws {
        let repository = try PlanRepository(inMemory: true)
        let now = Date()
        let task = PlanTask(title: "会超时", dueDate: now)
        repository.context.insert(task)
        repository.save()

        let startedSession = await repository.startFocus(taskID: task.id, minutes: 15, now: now)
        let session = try XCTUnwrap(startedSession)
        repository.expireStaleFocusSessions(now: now.addingTimeInterval(31 * 60))

        let updated = repository.focusSession(id: session.id)
        XCTAssertEqual(updated?.status, .timedOut)
        XCTAssertEqual(updated?.effectiveMinutes, 0)
    }

    @MainActor
    func testRecentFocusSessionsExposeCompletedHistory() async throws {
        let repository = try PlanRepository(inMemory: true)
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let task = PlanTask(title: "复盘", dueDate: yesterday)
        repository.context.insert(task)
        repository.save()

        let startedSession = await repository.startFocus(taskID: task.id, minutes: 15, now: yesterday)
        let session = try XCTUnwrap(startedSession)
        repository.completeFocusSession(id: session.id, now: yesterday.addingTimeInterval(12 * 60))

        let history = repository.recentFocusSessions(days: 7, endingOn: now)
        XCTAssertEqual(history.map(\.taskTitle), ["复盘"])
        XCTAssertEqual(history.first?.effectiveMinutes, 12)
    }

    @MainActor
    func testUpcomingTasksExposeFuturePlansOnly() throws {
        let repository = try PlanRepository(inMemory: true)
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let later = Calendar.current.date(byAdding: .day, value: 3, to: today)!
        let completed = PlanTask(title: "已完成未来任务", dueDate: tomorrow, isCompleted: true)
        let future = PlanTask(title: "明天计划", dueDate: tomorrow)
        let farther = PlanTask(title: "三天后计划", dueDate: later)
        let todayTask = PlanTask(title: "今天计划", dueDate: today)
        repository.context.insert(completed)
        repository.context.insert(future)
        repository.context.insert(farther)
        repository.context.insert(todayTask)
        repository.save()

        let upcoming = repository.upcomingTasks(days: 7, from: today)

        XCTAssertEqual(upcoming.map(\.title), ["明天计划", "三天后计划"])
    }

    @MainActor
    func testDisablingTemplateKeepsTodayAndCompletedHistoryButRemovesFutureGeneratedTasks() async throws {
        let repository = try PlanRepository(inMemory: true)
        let template = PlanTemplate(title: "复盘", cadence: .daily)
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let later = Calendar.current.date(byAdding: .day, value: 2, to: today)!
        let todayTask = PlanTask(title: "今天", dueDate: today, templateID: template.id)
        let futureTask = PlanTask(title: "明天", dueDate: tomorrow, templateID: template.id)
        let completedFutureTask = PlanTask(
            title: "已完成",
            dueDate: later,
            isCompleted: true,
            completedAt: later,
            templateID: template.id
        )
        repository.context.insert(template)
        repository.context.insert(todayTask)
        repository.context.insert(futureTask)
        repository.context.insert(completedFutureTask)
        repository.save()

        await repository.setTemplateEnabled(id: template.id, isEnabled: false)

        XCTAssertFalse(repository.template(id: template.id)?.isEnabled == true)
        XCTAssertNotNil(repository.task(id: todayTask.id))
        XCTAssertNil(repository.task(id: futureTask.id))
        XCTAssertNotNil(repository.task(id: completedFutureTask.id))
    }

    // MARK: - DateRules Tests

    func testDayBoundsReturnsStartOfDayToNextDay() {
        let calendar = Calendar(identifier: .gregorian)
        let date = DateComponents(calendar: calendar, year: 2026, month: 5, day: 19, hour: 14, minute: 30).date!
        let bounds = DateRules.dayBounds(for: date, calendar: calendar)

        XCTAssertEqual(calendar.component(.hour, from: bounds.start), 0)
        XCTAssertEqual(calendar.component(.minute, from: bounds.start), 0)
        XCTAssertEqual(calendar.component(.day, from: bounds.start), 19)
        XCTAssertEqual(calendar.component(.day, from: bounds.end), 20)
        XCTAssertEqual(calendar.component(.hour, from: bounds.end), 0)
    }

    func testReminderDateSetsHourAndMinuteFromTemplate() {
        let calendar = Calendar(identifier: .gregorian)
        let day = DateComponents(calendar: calendar, year: 2026, month: 5, day: 19).date!
        let template = PlanTemplate(title: "Test", cadence: .daily, defaultReminderHour: 14, defaultReminderMinute: 30)

        let reminder = DateRules.reminderDate(for: day, template: template, calendar: calendar)

        XCTAssertNotNil(reminder)
        XCTAssertEqual(calendar.component(.hour, from: reminder!), 14)
        XCTAssertEqual(calendar.component(.minute, from: reminder!), 30)
        XCTAssertEqual(calendar.component(.day, from: reminder!), 19)
    }

    // MARK: - PlanStore Tests

    @MainActor
    func testPlanStoreRefreshPopulatesTodayTasks() throws {
        let repository = try PlanRepository(inMemory: true)
        let store = PlanStore(repository: repository)
        let task = PlanTask(title: "今天的事", dueDate: Date())
        repository.context.insert(task)
        repository.save()

        store.refresh()

        XCTAssertEqual(store.todayTasks.count, 1)
        XCTAssertEqual(store.todayTasks.first?.title, "今天的事")
    }

    @MainActor
    func testPlanStoreToggleSetsAndClearsCelebrate() async throws {
        let repository = try PlanRepository(inMemory: true)
        let store = PlanStore(repository: repository)
        let task = PlanTask(title: "测试完成", dueDate: Date())
        repository.context.insert(task)
        repository.save()
        store.refresh()

        await store.toggle(task)

        XCTAssertTrue(task.isCompleted)
    }

    @MainActor
    func testPlanStoreDeleteAttachmentRemovesFromTask() async throws {
        let repository = try PlanRepository(inMemory: true)
        let store = PlanStore(repository: repository)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("plan-test-del-\(UUID().uuidString).txt")
        try "image".write(to: source, atomically: true, encoding: .utf8)

        await repository.createTask(title: "有附件", dueDate: Date(), reminderDate: nil, notes: "", priority: .b, attachmentURLs: [source])
        store.refresh()

        let task = store.todayTasks.first!
        XCTAssertEqual(task.attachments.count, 1)

        let attachment = task.attachments[0]
        store.deleteAttachment(attachment, from: task)

        XCTAssertEqual(task.attachments.count, 0)
    }
}
