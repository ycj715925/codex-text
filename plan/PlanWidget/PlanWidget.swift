import SwiftUI
import WidgetKit

struct PlanWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: PlanWidgetSnapshot

    var progress: Double {
        snapshot.progress
    }

    var progressText: String {
        snapshot.progressText
    }

    var tasks: [WidgetTaskSnapshot] {
        snapshot.tasks
    }

    var totalCount: Int {
        snapshot.totalCount
    }

    var nextTask: WidgetTaskSnapshot? {
        tasks.first { !$0.isCompleted }
    }
}

struct PlanWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlanWidgetEntry {
        PlanWidgetEntry(
            date: Date(),
            snapshot: PlanWidgetSnapshot(
                date: Date(),
                tasks: [WidgetTaskSnapshot(id: UUID(), title: "整理今天最重要的事", timeText: "09:00", isCompleted: false, priorityRaw: "S")],
                completedCount: 0,
                totalCount: 1
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PlanWidgetEntry) -> Void) {
        completion(Self.currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlanWidgetEntry>) -> Void) {
        let entry = Self.currentEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private static func currentEntry() -> PlanWidgetEntry {
        PlanWidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.read())
    }
}

struct PlanWidget: Widget {
    let kind = "PlanWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlanWidgetProvider()) { entry in
            PlanWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetGlassBackground()
                }
        }
        .configurationDisplayName("计划")
        .description("查看今天计划，并在桌面直接完成或延期。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct PlanWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PlanWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            small
        default:
            medium
        }
    }

    private var small: some View {
        Link(destination: AppConstants.DeepLink.today) {
            GeometryReader { proxy in
                let headerHeight = max(54, proxy.size.height * 0.26)

                VStack(alignment: .leading, spacing: 0) {
                    SmallWidgetHeader(
                        progress: entry.progress,
                        progressText: entry.progressText,
                        width: proxy.size.width
                    )
                    .frame(height: headerHeight)
                    .frame(maxWidth: .infinity)
                    .background(SmallWidgetHeaderBackground())

                    SmallWidgetBody(
                        tasks: Array(entry.tasks.prefix(4)),
                        isFocusing: entry.snapshot.isFocusing,
                        focusTitle: entry.snapshot.focusTitle
                    )
                        .padding(.leading, proxy.size.width * 0.105)
                        .padding(.trailing, proxy.size.width * 0.085)
                        .padding(.top, proxy.size.height * 0.045)
                        .padding(.bottom, proxy.size.height * 0.08)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .widgetURL(AppConstants.DeepLink.today)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WidgetHeader(progress: entry.progress, progressText: entry.progressText)
                Spacer()
                Link(destination: AppConstants.DeepLink.add) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.18), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
                }
            }

            if entry.snapshot.isFocusing, let focusTitle = entry.snapshot.focusTitle {
                Text("正在专注：\(focusTitle)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.14), in: Capsule())
            }

            if entry.tasks.isEmpty {
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Text("今天还没有计划")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("点右上角添加第一件事")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
            } else {
                VStack(spacing: 8) {
                    ForEach(entry.tasks) { task in
                        WidgetTaskLine(task: task, showsActions: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct WidgetHeader: View {
    let progress: Double
    let progressText: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist.checked")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.92))
            Text("计划")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white.opacity(0.94))
            Spacer(minLength: 0)
            MiniProgressRing(progress: progress, text: progressText)
                .frame(width: 30, height: 30)
        }
    }
}

private struct SmallWidgetHeader: View {
    let progress: Double
    let progressText: String
    let width: CGFloat

    var body: some View {
        HStack(alignment: .center) {
            Text("计划")
                .font(.system(size: max(17, width * 0.115), weight: .heavy))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
            SmallWidgetProgressRing(progress: progress, text: progressText)
                .frame(width: max(24, width * 0.145), height: max(24, width * 0.145))
        }
        .padding(.leading, width * 0.135)
        .padding(.trailing, width * 0.115)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct SmallWidgetProgressRing: View {
    let progress: Double
    let text: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 2.6)
            Circle()
                .trim(from: 0, to: max(0.04, progress))
                .stroke(.white.opacity(progress == 0 ? 0.3 : 0.94), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(text)
                .font(.system(size: 7, weight: .heavy))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
    }
}

private struct SmallWidgetHeaderBackground: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    .black.opacity(0.16),
                    .black.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct SmallWidgetBody: View {
    let tasks: [WidgetTaskSnapshot]
    let isFocusing: Bool
    let focusTitle: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            WidgetPageLines()

            if isFocusing, let focusTitle {
                VStack(alignment: .leading, spacing: 8) {
                    Text("正在专注")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.66))
                    Text(focusTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2)
                }
                .padding(.top, 4)
            } else if tasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今天还没有计划")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("点击添加第一件事")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                }
                .padding(.top, 9)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        SmallWidgetTaskLine(task: task)
                            .frame(height: 26)

                        if index < tasks.count - 1 {
                            WidgetPageRule()
                        }
                    }
                }
            }
        }
    }
}

private struct SmallWidgetTaskLine: View {
    let task: WidgetTaskSnapshot

    var body: some View {
        HStack(spacing: 6) {
            WidgetPriorityBadge(priority: task.priority, size: 18)

            Text(task.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(task.isCompleted ? 0.5 : 0.9))
                .lineLimit(1)
                .strikethrough(task.isCompleted)

            Spacer(minLength: 0)
        }
        .frame(minHeight: 20)
    }
}

private struct WidgetPageRule: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.14))
            .frame(height: 1)
    }
}

private struct WidgetPageLines: View {
    var body: some View {
        VStack(spacing: 25) {
            ForEach(0..<4, id: \.self) { _ in
                WidgetPageRule()
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 26)
    }
}

private struct WidgetTaskLine: View {
    let task: WidgetTaskSnapshot
    let showsActions: Bool

    var body: some View {
        HStack(spacing: 8) {
            if showsActions {
                Button(intent: CompleteTaskIntent(taskID: task.id.uuidString)) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.isCompleted ? .white : .white.opacity(0.62))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.isCompleted ? "标记未完成" : "标记完成")
            }

            WidgetPriorityBadge(priority: task.priority, size: 20)

            Text(task.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(task.isCompleted ? 0.5 : 0.9))
                .lineLimit(showsActions ? 1 : 2)
                .strikethrough(task.isCompleted)

            Spacer(minLength: 0)

            if !task.timeText.isEmpty {
                Text(task.timeText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
            }

            if showsActions {
                Button(intent: SnoozeTaskIntent(taskID: task.id.uuidString, minutes: 30)) {
                    Image(systemName: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.68))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("延后 30 分钟")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct WidgetPriorityBadge: View {
    let priority: TaskPriority
    let size: CGFloat

    var body: some View {
        Text(priority.rawValue)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(priorityColor, in: Circle())
    }

    private var priorityColor: Color {
        switch priority {
        case .s:
            return .orange.opacity(0.92)
        case .a:
            return .red.opacity(0.9)
        case .b:
            return .blue.opacity(0.85)
        case .c:
            return .teal.opacity(0.82)
        }
    }
}

private struct MiniProgressRing: View {
    let progress: Double
    let text: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.04, progress))
                .stroke(.white.opacity(progress == 0 ? 0.24 : 0.92), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(text)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white.opacity(0.86))
        }
    }
}

private struct WidgetGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark ? [
                    Color(red: 0.18, green: 0.22, blue: 0.30).opacity(0.85),
                    Color(red: 0.12, green: 0.15, blue: 0.22).opacity(0.78),
                    Color(red: 0.08, green: 0.10, blue: 0.16).opacity(0.72)
                ] : [
                    Color(red: 0.64, green: 0.74, blue: 0.82).opacity(0.72),
                    Color(red: 0.42, green: 0.50, blue: 0.64).opacity(0.62),
                    Color(red: 0.24, green: 0.31, blue: 0.42).opacity(0.58)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [.white.opacity(colorScheme == .dark ? 0.12 : 0.34), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 180
            )
            RadialGradient(
                colors: [Color(red: 0.50, green: 0.83, blue: 0.86).opacity(colorScheme == .dark ? 0.10 : 0.26), .clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 190
            )
            ContainerRelativeShape()
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.12 : 0.28), lineWidth: 1)
        }
    }
}
