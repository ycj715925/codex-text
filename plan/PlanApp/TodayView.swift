import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: PlanStore

    private var completedCount: Int {
        store.todayTasks.filter(\.isCompleted).count
    }

    private var progress: Double {
        guard !store.todayTasks.isEmpty else { return 0 }
        return Double(completedCount) / Double(store.todayTasks.count)
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    focusArea
                    weeklyTrend
                    historyAndFuture
                    taskSections
                }
                .padding(24)
            }

            feedbackOverlay
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: store.celebrate)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: store.focusFeedback)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text("今天")
                    .font(.system(size: 34, weight: .bold))
                HStack(spacing: 12) {
                    ProgressView(value: progress)
                        .frame(width: 180)
                    Text("\(completedCount)/\(store.todayTasks.count)")
                        .font(.headline)
                    Text("连续 \(store.streak) 天")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                store.showQuickAdd()
            } label: {
                Label("新增", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n")
        }
    }

    @ViewBuilder
    private var focusArea: some View {
        if let session = store.activeFocusSession {
            ActiveFocusCard(session: session)
                .environmentObject(store)
        } else if let task = store.focusCandidate() {
            FocusCandidateCard(task: task, isFallback: store.isUsingSnoozedFallback())
                .environmentObject(store)
        } else {
            EmptyFocusCard()
                .environmentObject(store)
        }
    }

    private var weeklyTrend: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("本周节奏")
                    .font(.headline)
                Spacer()
                Text("完成率 \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.usageDayCount < 7 {
                Text("再用 \(7 - store.usageDayCount) 天就能看到你的节奏")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(store.progressSummaries) { item in
                        DailyTrendBar(summary: item)
                    }
                }
                .frame(height: 74)
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var taskSections: some View {
        VStack(alignment: .leading, spacing: 16) {
            TaskSection(kind: .now, tasks: store.nowTasks())
                .environmentObject(store)
            TaskSection(kind: .snoozed, tasks: store.snoozedTasks())
                .environmentObject(store)
            TaskSection(kind: .completed, tasks: store.completedTasks())
                .environmentObject(store)
        }
    }

    private var historyAndFuture: some View {
        HStack(alignment: .top, spacing: 14) {
            FocusHistoryPanel(sessions: store.recentFocusSessions)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            UpcomingPlanPanel(tasks: store.upcomingTasks)
                .environmentObject(store)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var feedbackOverlay: some View {
        if store.celebrate {
            feedbackText("完成 +1")
        }
        if let focusFeedback = store.focusFeedback {
            feedbackText(focusFeedback)
        }
    }

    private func feedbackText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 34, weight: .bold))
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .transition(.scale.combined(with: .opacity))
    }
}

private struct FocusCandidateCard: View {
    @EnvironmentObject private var store: PlanStore
    let task: PlanTask
    let isFallback: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("现在做")
                    .font(.title2.weight(.bold))
                Spacer()
                PriorityBadge(priority: task.priority)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(2)
                if isFallback {
                    Text("这个可以先开始")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Menu {
                    Button("15 分钟") { Task { await store.startFocus(task: task, minutes: 15) } }
                    Button("25 分钟") { Task { await store.startFocus(task: task, minutes: 25) } }
                    Button("45 分钟") { Task { await store.startFocus(task: task, minutes: 45) } }
                } label: {
                    Label("开始专注", systemImage: "timer")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await store.toggle(task) }
                } label: {
                    Label("完成", systemImage: "checkmark")
                }
                .buttonStyle(.bordered)

                SnoozeMenu(task: task)
                    .environmentObject(store)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ActiveFocusCard: View {
    @EnvironmentObject private var store: PlanStore
    let session: FocusSession
    @State private var didExpire = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = session.remainingSeconds(at: context.date)
            let expired = session.shouldTimeOut(at: context.date)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(expired ? "专注已超时" : "正在专注")
                        .font(.title2.weight(.bold))
                    Spacer()
                    Text(format(seconds: remaining))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                Text(session.taskTitle)
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(2)

                Text(expired ? "已超过计划时长 2 倍，记录为超时未操作" : "保持这个任务在前面，先推进一小段")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        Task { await store.completeFocus() }
                    } label: {
                        Label("完成专注", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(expired)

                    Button {
                        store.abandonFocus()
                    } label: {
                        Label("放弃", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .task(id: expired) {
                guard expired, !didExpire else { return }
                didExpire = true
                store.expireFocusIfNeeded()
            }
        }
    }

    private func format(seconds: Int) -> String {
        let minutes = seconds / 60
        let seconds = seconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct EmptyFocusCard: View {
    @EnvironmentObject private var store: PlanStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今天没有计划，要加一个吗？")
                .font(.title2.weight(.bold))
            Button {
                store.showQuickAdd()
            } label: {
                Label("添加第一件事", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private enum TaskSectionKind {
    case now, snoozed, completed

    var title: String {
        switch self {
        case .now: return "现在"
        case .snoozed: return "稍后"
        case .completed: return "已完成"
        }
    }

    var emptyText: String {
        switch self {
        case .now: return "当前没有要立刻处理的计划"
        case .snoozed: return "没有被延期的计划"
        case .completed: return "完成后会出现在这里"
        }
    }
}

private struct TaskSection: View {
    @EnvironmentObject private var store: PlanStore
    let kind: TaskSectionKind
    let tasks: [PlanTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(kind.title)
                    .font(.headline)
                Text("\(tasks.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if tasks.isEmpty {
                Text(kind.emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(tasks) { task in
                    TaskRow(task: task)
                        .environmentObject(store)
                }
            }
        }
    }
}

private struct SnoozeMenu: View {
    @EnvironmentObject private var store: PlanStore
    let task: PlanTask

    var body: some View {
        Menu {
            Button("15 分钟") { Task { await store.snooze(task, minutes: 15) } }
            Button("30 分钟") { Task { await store.snooze(task, minutes: 30) } }
            Button("今晚") { Task { await store.snoozeUntilTonight(task) } }
        } label: {
            Label("稍后", systemImage: "clock")
        }
        .buttonStyle(.bordered)
    }
}

private struct FocusHistoryPanel: View {
    let sessions: [FocusSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近专注")
                .font(.headline)

            if sessions.isEmpty {
                Text("完成一次专注后，这里会保留最近几天的记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(sessions.prefix(4)) { session in
                    HStack(spacing: 10) {
                        Image(systemName: iconName(for: session.status))
                            .font(.headline)
                            .foregroundStyle(color(for: session.status))
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.taskTitle)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(detailText(for: session))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func detailText(for session: FocusSession) -> String {
        let minutes = session.status == .completed ? session.effectiveMinutes : session.actualMinutes
        let day = session.startDate.formatted(.dateTime.weekday(.wide).hour().minute())
        return "\(day) · \(statusText(session.status)) · \(minutes) 分钟"
    }

    private func statusText(_ status: FocusSessionStatus) -> String {
        switch status {
        case .inProgress:
            return "进行中"
        case .completed:
            return "已完成"
        case .abandoned:
            return "已放弃"
        case .timedOut:
            return "超时未操作"
        }
    }

    private func iconName(for status: FocusSessionStatus) -> String {
        switch status {
        case .completed:
            return "checkmark.circle.fill"
        case .abandoned:
            return "xmark.circle.fill"
        case .timedOut:
            return "exclamationmark.circle.fill"
        case .inProgress:
            return "timer.circle.fill"
        }
    }

    private func color(for status: FocusSessionStatus) -> Color {
        switch status {
        case .completed:
            return .green
        case .abandoned:
            return .secondary
        case .timedOut:
            return .orange
        case .inProgress:
            return .accentColor
        }
    }
}

private struct UpcomingPlanPanel: View {
    @EnvironmentObject private var store: PlanStore
    let tasks: [PlanTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("未来安排")
                    .font(.headline)
                Spacer()
                Text("7 天")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if tasks.isEmpty {
                Text("未来几天还没有安排")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(tasks.prefix(5)) { task in
                    HStack(spacing: 10) {
                        PriorityBadge(priority: task.priority)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(task.dueDate.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.selectedTab = .plan
                        store.selectDate(task.dueDate)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DailyTrendBar: View {
    let summary: DailyProgressSummary

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                VStack {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(summary.focusMinutes > 0 ? Color.accentColor : Color.secondary.opacity(0.45))
                        .frame(height: max(4, proxy.size.height * summary.completionRatio))
                }
            }
            .frame(width: 18)

            Text(summary.day.formatted(.dateTime.weekday(.narrow)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
