import SwiftUI

struct TaskEditorView: View {
    @EnvironmentObject private var store: PlanStore
    @Environment(\.dismiss) private var dismiss

    let task: PlanTask?

    @State private var title: String
    @State private var dueDate: Date
    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var notes: String
    @State private var priority: TaskPriority
    @State private var pickedURLs: [URL] = []
    @State private var isImporting = false
    @State private var isConfirmingDelete = false

    init(task: PlanTask?) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _dueDate = State(initialValue: task?.dueDate ?? Date())
        _hasReminder = State(initialValue: task?.reminderDate != nil)
        _reminderDate = State(initialValue: task?.reminderDate ?? Date())
        _notes = State(initialValue: task?.notes ?? "")
        _priority = State(initialValue: task?.priority ?? .b)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(task == nil ? "新增计划" : "编辑计划")
                .font(.title2.weight(.semibold))

            TextField("要做什么", text: $title)
                .textFieldStyle(.roundedBorder)

            Picker("重要程度", selection: $priority) {
                ForEach(TaskPriority.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            DatePicker("日期", selection: $dueDate)

            Toggle("提醒", isOn: $hasReminder)
            if hasReminder {
                DatePicker("提醒时间", selection: $reminderDate)
            }

            Text("记录")
                .font(.headline)
            TextEditor(text: $notes)
                .frame(minHeight: 100)
                .border(.separator)

            attachmentSection

            HStack {
                if task != nil {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }

                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button("保存") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 520)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                pickedURLs.append(contentsOf: urls)
            }
        }
        .confirmationDialog("删除这条计划？", isPresented: $isConfirmingDelete) {
            Button("删除", role: .destructive) {
                if let task {
                    store.delete(task)
                }
            }
        }
    }

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("图片")
                    .font(.headline)
                Spacer()
                Button {
                    isImporting = true
                } label: {
                    Label("上传图片", systemImage: "photo.badge.plus")
                }
            }

            if let task, !task.attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(task.attachments) { attachment in
                            AsyncImage(url: store.attachmentURL(for: attachment)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(.quaternary)
                            }
                            .frame(width: 82, height: 82)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    store.deleteAttachment(attachment, from: task)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white, .red)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("删除图片")
                                .offset(x: 6, y: -6)
                            }
                        }
                    }
                }
            }

            if !pickedURLs.isEmpty {
                Text("待添加 \(pickedURLs.count) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func save() async {
        await store.saveTask(
            task: task,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: dueDate,
            reminderDate: hasReminder ? reminderDate : nil,
            notes: notes,
            priority: priority,
            attachmentURLs: pickedURLs
        )
    }
}
