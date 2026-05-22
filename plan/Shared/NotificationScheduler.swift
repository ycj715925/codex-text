import Foundation
import UserNotifications

@MainActor
struct NotificationScheduler {
    static let shared = NotificationScheduler()

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    func schedule(task: PlanTask) async -> String? {
        guard !task.isCompleted, let reminderDate = task.reminderDate, reminderDate > Date() else {
            if let notificationID = task.notificationID {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
            }
            return nil
        }

        let identifier = task.notificationID ?? "task-\(task.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = task.notes.isEmpty ? "该处理这件事了。" : task.notes
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
        return identifier
    }

    func scheduleFocusEnd(session: FocusSession) async {
        guard session.status == .inProgress, session.plannedEndDate > Date() else { return }

        let identifier = focusIdentifier(sessionID: session.id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "专注时间到了"
        content.body = session.taskTitle
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: session.plannedEndDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancel(identifier: String?) {
        guard let identifier else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelFocus(sessionID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [focusIdentifier(sessionID: sessionID)])
    }

    private func focusIdentifier(sessionID: UUID) -> String {
        "focus-\(sessionID.uuidString)"
    }
}
