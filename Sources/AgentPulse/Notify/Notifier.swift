import Foundation
import UserNotifications

/// Системные баннеры: уважают Focus/DND. Без бандла (голый `swift run`) молча выключены —
/// `UNUserNotificationCenter` падает в процессе без bundle id.
@MainActor
final class Notifier {
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(id: String, title: String, body: String, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        center?.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func remove(id: String) {
        center?.removeDeliveredNotifications(withIdentifiers: [id])
    }
}
