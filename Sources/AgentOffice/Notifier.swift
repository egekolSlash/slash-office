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

    static var prefs: NotificationPrefs { NotificationPrefs.load(from: .standard) }

    /// Özel ses çalarken bırakılmasın diye tutulur.
    private static var player: NSSound?

    static func notifyWaiting(sessionID: String, title: String, reason: InputReason) {
        guard !NSApp.isActive else { return }
        let body = switch reason {
        case .question(let text): text.isEmpty ? String(localized: "Asking a question") : text
        case .permission: String(localized: "Waiting for permission")
        }
        alert(sessionID: sessionID, title: title, body: body, attention: .criticalRequest)
    }

    /// Ajan işini bitirdi: köşede bildirim, Dock zıplaması ve ses. Ayarlar'dan kapatılınca hiçbiri olmaz.
    static func notifyFinished(sessionID: String, title: String) {
        guard !NSApp.isActive, prefs.finished else { return }
        alert(sessionID: sessionID, title: title, body: String(localized: "Finished"), attention: .informationalRequest)
    }

    private static func alert(sessionID: String, title: String, body: String, attention: NSApplication.RequestUserAttentionType) {
        let prefs = prefs
        if prefs.dockBounce { NSApp.requestUserAttention(attention) }
        let sound = NotificationPolicy.sound(prefs, fileExists: FileManager.default.fileExists(atPath:))
        // Özel ses bildirimin sesi olamaz (UNNotificationSound yalnızca paket içi dosya çalar): kendimiz çalarız.
        if case .file(let url) = sound { play(url) }
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound == .system ? .default : nil
        content.userInfo = ["sessionID": sessionID]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: sessionID, content: content, trigger: nil))
    }

    // MARK: - Özel ses

    /// Seçilen ses buraya kopyalanır; kullanıcı aslını taşısa da silse de çalmaya devam eder.
    static var soundsDirectory: URL {
        SupportDirectory.current.appendingPathComponent("Sounds", isDirectory: true)
    }

    /// Ayarlar'daki önizleme: seçili sesi, yoksa sistem sesini çalar.
    static func playPreview() {
        if case .file(let url) = NotificationPolicy.sound(NotificationPrefs(soundFile: prefs.soundFile),
                                                         fileExists: FileManager.default.fileExists(atPath:)) {
            play(url)
        } else {
            NSSound.beep()
        }
    }

    /// Ayarlar'da gösterilen, seçilen dosyanın asıl adı.
    static let soundNameKey = "notifySoundName"

    /// Dosyayı destek klasörüne kopyalar ve tercihe yazar; önceki ses silinir.
    static func importSound(from source: URL) throws {
        guard let name = NotificationPolicy.storedSoundName(for: source.lastPathComponent),
              NSSound(contentsOf: source, byReference: true) != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
        let target = soundsDirectory.appendingPathComponent(name)
        // Dosyayı kopyala, sonra eskisini sil: kopya olmazsa eski ses kalır.
        let staging = soundsDirectory.appendingPathComponent(UUID().uuidString + "." + target.pathExtension)
        try fileManager.copyItem(at: source, to: staging)
        if let old = prefs.soundFile { try? fileManager.removeItem(atPath: old) }
        try? fileManager.removeItem(at: target)
        try fileManager.moveItem(at: staging, to: target)
        UserDefaults.standard.set(target.path, forKey: NotificationPrefs.soundFileKey)
        UserDefaults.standard.set(source.lastPathComponent, forKey: soundNameKey)
    }

    static func resetSound() {
        if let old = prefs.soundFile { try? FileManager.default.removeItem(atPath: old) }
        UserDefaults.standard.removeObject(forKey: NotificationPrefs.soundFileKey)
        UserDefaults.standard.removeObject(forKey: soundNameKey)
    }

    private static func play(_ url: URL) {
        player?.stop()
        player = NSSound(contentsOf: url, byReference: true)
        player?.play()
    }
}
