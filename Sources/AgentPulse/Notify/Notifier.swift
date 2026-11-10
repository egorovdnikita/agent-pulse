import AgentPulseCore
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

    func post(id: String, title: String, body: String, sound: Bool, host: String?, source: AgentEvent.Source? = nil, sessionID: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        if let host { content.userInfo[Self.hostKey] = host }
        if let source, let sessionID {
            content.userInfo["agentSource"] = source.rawValue
            content.userInfo["agentSession"] = sessionID
        }
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
        let source = (response.notification.request.content.userInfo["agentSource"] as? String).flatMap { AgentEvent.Source(rawValue: $0) }
        let sessionID = response.notification.request.content.userInfo["agentSession"] as? String
        completionHandler()
        DispatchQueue.main.async { AgentNavigation.open(source: source, sessionID: sessionID, host: host) }
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
