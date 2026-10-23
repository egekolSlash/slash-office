import Foundation

/// Bildirim tercihleri (Ayarlar › Bildirimler). Hepsi varsayılan olarak açık; özel ses yoksa sistem sesi çalar.
public struct NotificationPrefs: Equatable, Sendable {
    public static let finishedKey = "notifyFinished"
    public static let dockBounceKey = "notifyDockBounce"
    public static let soundKey = "notifySound"
    public static let soundFileKey = "notifySoundFile"

    /// Ajan işini bitirince bildirim gelsin.
    public var finished: Bool
    /// Bildirimde Dock simgesi zıplasın.
    public var dockBounce: Bool
    /// Bildirimde ses çalsın.
    public var sound: Bool
    /// Kullanıcının seçtiği ses dosyası (uygulamanın destek klasörüne kopyalanmış hâli); nil ise sistem sesi.
    public var soundFile: String?

    public init(finished: Bool = true, dockBounce: Bool = true, sound: Bool = true, soundFile: String? = nil) {
        self.finished = finished
        self.dockBounce = dockBounce
        self.sound = sound
        self.soundFile = soundFile
    }

    public static func load(from defaults: UserDefaults) -> NotificationPrefs {
        let flag = { (key: String) in defaults.object(forKey: key) as? Bool ?? true }
        let file = defaults.string(forKey: soundFileKey).flatMap { $0.isEmpty ? nil : $0 }
        return NotificationPrefs(finished: flag(finishedKey), dockBounce: flag(dockBounceKey), sound: flag(soundKey), soundFile: file)
    }
}

public enum NotificationPolicy {
    public enum Sound: Equatable, Sendable {
        case none
        case system
        case file(URL)
    }

    /// Seçilebilen ses dosyası türleri (NSSound'un çalabildikleri).
    public static let soundExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "caf"]

    /// Tur cevapla bitti mi: çalışırken (ya da izin/soru beklerken) Stop geldi ve oturum boşta kaldı.
    /// Esc ile kesilen tur (Stop gelmez) ve zaten boştaki oturuma gelen Stop sayılmaz.
    /// Arka planda iş sürüyorsa (`background > 0`) henüz bitmiş sayılmaz; son iş bitince Claude'un açtığı turun Stop'u bildirir.
    public static func finished(previous: AgentState?, events: [AgentEvent], current: AgentState?, background: Int = 0) -> Bool {
        guard current == .idle, background == 0, events.contains(where: { if case .turnEnded = $0 { true } else { false } }) else { return false }
        switch previous {
        case .working, .waiting: return true
        default: return false
        }
    }

    /// Çalınacak ses: kapalıysa hiç; seçilen dosya hâlâ duruyorsa o; yoksa sistem sesi.
    public static func sound(_ prefs: NotificationPrefs, fileExists: (String) -> Bool) -> Sound {
        guard prefs.sound else { return .none }
        if let path = prefs.soundFile, fileExists(path) { return .file(URL(fileURLWithPath: path)) }
        return .system
    }

    /// Seçilen dosyanın destek klasöründeki adı; tek dosya tutulur, eskisinin yerine geçer. Ses değilse nil.
    public static func storedSoundName(for fileName: String) -> String? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return soundExtensions.contains(ext) ? "notification.\(ext)" : nil
    }
}
