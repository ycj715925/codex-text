import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var store: PlanStore
    @State private var templateTitle = ""
    @State private var cadence: RepeatCadence = .daily
    @State private var selectedWeekdays: Set<Int> = [2]
    @State private var monthDay = 1
    @State private var reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var templateToDelete: PlanTemplate?
    @State private var isConfirmingTemplateDelete = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                Text("计划")
                    .font(.system(size: 30, weight: .bold))

                DatePicker("选择日期", selection: Binding(
                    get: { store.selectedDate },
                    set: { store.selectDate($0) }
                ), displayedComponents: .date)
                .datePickerStyle(.graphical)

                List(store.plannedTasks) { task in
                    TaskRow(task: task)
                        .environmentObject(store)
                }
                .listStyle(.plain)
            }
            .padding(24)
            .frame(minWidth: 460)

            VStack(alignment: .leading, spacing: 18) {
                Text("重复模板")
                    .font(.title2.weight(.semibold))

                templateForm

                Divider()

                List(store.templates) { template in
                    templateRow(template)
                }
                .listStyle(.plain)
            }
            .padding(24)
            .frame(minWidth: 320)
        }
        .confirmationDialog("删除这个重复模板？", isPresented: $isConfirmingTemplateDelete) {
            Button("删除", role: .destructive) {
                if let templateToDelete {
                    store.deleteTemplate(templateToDelete)
                }
                templateToDelete = nil
            }
        }
    }

    private var templateForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("要重复做的事", text: $templateTitle)

            Picker("频率", selection: $cadence) {
                ForEach(RepeatCadence.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if cadence == .weekly {
                weekdayPicker
            }

            if cadence == .monthly {
                Stepper("每月第 \(monthDay) 天", value: $monthDay, in: 1...31)
            }

            DatePicker("提醒时间", selection: $reminderTime, displayedComponents: .hourAndMinute)

            Button {
                Task { await addTemplate() }
            } label: {
                Label("添加模板", systemImage: "plus")
            }
            .disabled(templateTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var weekdayPicker: some View {
        HStack {
            ForEach(1...7, id: \.self) { weekday in
                Button(weekdayLabel(weekday)) {
                    if selectedWeekdays.contains(weekday) {
                        selectedWeekdays.remove(weekday)
                    } else {
                        selectedWeekdays.insert(weekday)
                    }
                }
                .buttonStyle(.bordered)
                .tint(selectedWeekdays.contains(weekday) ? .accentColor : .secondary)
            }
        }
    }

    private func templateRow(_ template: PlanTemplate) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.title)
                    .font(.headline)
                Text(templateSummary(template))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("启用", isOn: Binding(
                get: { template.isEnabled },
                set: { isEnabled in
                    Task { await store.setTemplateEnabled(template, isEnabled: isEnabled) }
                }
            ))
            .labelsHidden()

            Button(role: .destructive) {
                templateToDelete = template
                isConfirmingTemplateDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除模板")
        }
        .padding(.vertical, 4)
    }

    private func addTemplate() async {
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        await store.createTemplate(
            title: templateTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            cadence: cadence,
            weekdays: Array(selectedWeekdays).sorted(),
            monthDay: monthDay,
            hour: components.hour ?? 9,
            minute: components.minute ?? 0
        )
        templateTitle = ""
    }

    private func templateSummary(_ template: PlanTemplate) -> String {
        switch template.cadence {
        case .daily:
            return "每天 \(String(format: "%02d:%02d", template.defaultReminderHour, template.defaultReminderMinute))"
        case .weekly:
            let days = template.weekdays.map(weekdayLabel).joined(separator: "、")
            return "每周 \(days)"
        case .monthly:
            return "每月第 \(template.monthDay) 天"
        }
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        let labels = [1: "日", 2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六"]
        return labels[weekday] ?? "\(weekday)"
    }
}
