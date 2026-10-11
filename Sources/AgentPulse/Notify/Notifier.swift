import AppKit
import Foundation
import UserNotifications

/// Системные баннеры: уважают Focus/DND. Без бандла (голый `swift run`) молча выключены —
/// `UNUserNotificationCenter` падает в процессе без bundle id.
/// Клик по баннеру открывает приложение, в котором живёт агент.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    nonisolated private static let hostKey = "host"

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func requestAuthorization() {
        center?.delegate = self
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(id: String, title: String, body: String, sound: Bool, host: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        if let host { content.userInfo = [Self.hostKey: host] }
        center?.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func remove(id: String) {
        center?.removeDeliveredNotifications(withIdentifiers: [id])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let host = response.notification.request.content.userInfo[Self.hostKey] as? String
        completionHandler()
        guard let host else { return }
        DispatchQueue.main.async {
            NSRunningApplication.runningApplications(withBundleIdentifier: host).first?.activate()
        }
    }

    /// Показываем баннер, даже если Agent Pulse вдруг активен (например, открыт MascotLab).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
