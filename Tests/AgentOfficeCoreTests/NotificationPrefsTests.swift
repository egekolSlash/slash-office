import Foundation
import Testing
@testable import AgentOfficeCore

/// Ajan işini bitirince bildirim, Dock zıplaması ve ses (Ayarlar › Bildirimler).
@Suite struct NotificationPrefsTests {
    static func defaults() -> UserDefaults {
        let name = "NotificationPrefsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func everythingIsOnByDefault() {
        let prefs = NotificationPrefs.load(from: Self.defaults())
        #expect(prefs == NotificationPrefs(finished: true, dockBounce: true, sound: true, soundFile: nil))
    }

    @Test func loadsStoredValues() {
        let defaults = Self.defaults()
        defaults.set(false, forKey: NotificationPrefs.finishedKey)
        defaults.set(false, forKey: NotificationPrefs.dockBounceKey)
        defaults.set(false, forKey: NotificationPrefs.soundKey)
        defaults.set("/tmp/ding.mp3", forKey: NotificationPrefs.soundFileKey)
        let prefs = NotificationPrefs.load(from: defaults)
        #expect(prefs == NotificationPrefs(finished: false, dockBounce: false, sound: false, soundFile: "/tmp/ding.mp3"))
    }

    @Test func emptySoundFileMeansDefault() {
        let defaults = Self.defaults()
        defaults.set("", forKey: NotificationPrefs.soundFileKey)
        #expect(NotificationPrefs.load(from: defaults).soundFile == nil)
    }

    /// Çalışan tur Stop ile bitti: bildirilir.
    @Test func turnThatEndsIsAFinish() {
        #expect(NotificationPolicy.finished(previous: .working(tool: "Bash"), events: [.turnEnded], current: .idle))
    }

    /// Esc ile kesilen tur, boşta oturumda gelen Stop, ya da soru açıkken gelen Stop bildirilmez.
    @Test func interruptsAndIdleStopsAreNotFinishes() {
        #expect(!NotificationPolicy.finished(previous: .working(tool: nil), events: [.interrupted], current: .idle))
        #expect(!NotificationPolicy.finished(previous: .working(tool: nil), events: [.inputIdle], current: .idle))
        #expect(!NotificationPolicy.finished(previous: .idle, events: [.turnEnded], current: .idle))
        #expect(!NotificationPolicy.finished(previous: nil, events: [.turnEnded], current: .idle))
        #expect(!NotificationPolicy.finished(previous: .working(tool: nil), events: [.turnEnded], current: .exited))
    }

    /// İzin isteyip cevap alan tur da sonunda bitmiş sayılır.
    @Test func turnEndingAfterAPermissionIsAFinish() {
        #expect(NotificationPolicy.finished(previous: .waiting(.permission("Bash")), events: [.turnEnded], current: .idle))
    }

    @Test func soundChoice() {
        let exists: (String) -> Bool = { $0 == "/s/ding.mp3" }
        var prefs = NotificationPrefs()
        #expect(NotificationPolicy.sound(prefs, fileExists: exists) == .system)
        prefs.soundFile = "/s/ding.mp3"
        #expect(NotificationPolicy.sound(prefs, fileExists: exists) == .file(URL(fileURLWithPath: "/s/ding.mp3")))
        // Dosya silinmişse sistem sesine düşer.
        prefs.soundFile = "/s/gone.mp3"
        #expect(NotificationPolicy.sound(prefs, fileExists: exists) == .system)
        prefs.sound = false
        prefs.soundFile = "/s/ding.mp3"
        #expect(NotificationPolicy.sound(prefs, fileExists: exists) == .none)
    }

    @Test func storedSoundNameIsSafe() {
        #expect(NotificationPolicy.storedSoundName(for: "My Ding.MP3") == "notification.mp3")
        #expect(NotificationPolicy.storedSoundName(for: "chime.m4a") == "notification.m4a")
        #expect(NotificationPolicy.storedSoundName(for: "noext") == nil)
        #expect(NotificationPolicy.storedSoundName(for: "evil.exe") == nil)
    }
}
