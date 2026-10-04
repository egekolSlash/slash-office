import AgentOfficeCore
import AppKit

@MainActor
enum Notifier {
    /// Dock simgesinde bekleyen ajan sayısı; sıfırsa rozet kalkar.
    static func updateBadge(waiting: Int) {
        NSApp.dockTile.badgeLabel = waiting > 0 ? "\(waiting)" : nil
    }

    /// Task 8'de macOS bildirimi gönderecek.
    static func notifyWaiting(sessionID: String, title: String, reason: InputReason) {}
}
