import SwiftUI

struct TaskRow: View {
    @EnvironmentObject private var store: PlanStore
    let task: PlanTask

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await store.toggle(task) }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    PriorityBadge(priority: task.priority)

                    Text(task.title)
                        .font(.headline)
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                }

                HStack(spacing: 10) {
                    if let reminderDate = task.reminderDate {
                        Label(reminderDate.formatted(date: .omitted, time: .shortened), systemImage: "bell")
                    }
                    if let snoozedUntil = task.snoozedUntil, snoozedUntil > Date() {
                        Label("稍后 \(snoozedUntil.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                    }
                    if !task.notes.isEmpty {
                        Label("备注", systemImage: "note.text")
                    }
                    if !task.attachments.isEmpty {
                        Label("\(task.attachments.count)", systemImage: "photo")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button("15 分钟") { Task { await store.snooze(task, minutes: 15) } }
                Button("30 分钟") { Task { await store.snooze(task, minutes: 30) } }
                Button("今晚") { Task { await store.snoozeUntilTonight(task) } }
            } label: {
                Image(systemName: "clock")
            }
            .help("稍后提醒")
            .accessibilityLabel("稍后提醒")
            .buttonStyle(.borderless)

            Button {
                store.edit(task)
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("编辑")
            .accessibilityLabel("编辑")
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PriorityBadge: View {
    let priority: TaskPriority

    var body: some View {
        Text(priority.rawValue)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(priorityColor, in: Circle())
    }

    private var priorityColor: Color {
        switch priority {
        case .s:
            return .orange
        case .a:
            return .red
        case .b:
            return .blue
        case .c:
            return .teal
        }
    }
}
