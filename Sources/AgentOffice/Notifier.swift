import AgentOfficeCore
import AppKit
import UserNotifications

@MainActor
enum Notifier {
    /// Dock simgesinde bekleyen ajan sayısı; sıfırsa rozet kalkar.
    static func updateBadge(waiting: Int) {
        NSApp.dockTile.badgeLabel = waiting > 0 ? "\(waiting)" : nil
    }

    /// Paketsiz (`swift run`) süreçte UNUserNotificationCenter kullanılamaz; sadece .app içinde çalışır.
    static var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    static func notifyWaiting(sessionID: String, title: String, reason: InputReason) {
        guard canNotify, !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = switch reason {
        case .question(let text): text.isEmpty ? "Bir soru soruyor" : text
        case .permission: "İzin bekliyor"
        }
        content.sound = .default
        content.userInfo = ["sessionID": sessionID]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: sessionID, content: content, trigger: nil))
    }
}
