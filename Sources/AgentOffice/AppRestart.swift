import AgentOfficeCore
import AppKit

/// Uygulamaya özel dil ayarı ve yeniden başlatma (dil ancak yeniden açılışta geçerli olur).
@MainActor
enum AppRestart {
    /// Uygulamanın kendi ayarındaki dil (genel sistem listesi değil).
    static var language: AppLanguage {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
        return AppLanguage.from(appleLanguages: domain?["AppleLanguages"] as? [String])
    }

    static func apply(_ language: AppLanguage) {
        if let languages = language.appleLanguages {
            UserDefaults.standard.set(languages, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    /// Çalışan ajan varsa önce sorar; onaylanırsa uygulama kapanınca yenisi açılır. Yeni kopya eskisi kapanmadan
    /// açılırsa hook sunucusu çakışır; bu yüzden bekleyen küçük bir kabuk açar. `false`: yeniden açılamadı.
    @discardableResult
    static func relaunch(runningAgents: Int) -> Bool {
        if runningAgents > 0 {
            let alert = NSAlert()
            alert.messageText = String(localized: "Restart Slash Office?")
            alert.informativeText = String(localized: "\(runningAgents) running agents will be stopped. You can resume them after the restart.")
            alert.addButton(withTitle: String(localized: "Restart"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return true }
        }
        let bundle = Bundle.main.bundlePath
        guard bundle.hasSuffix(".app") else { return fail() }
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", bundle]
        do { try process.run() } catch { return fail() }
        NSApp.terminate(nil)
        return true
    }

    private static func fail() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Please restart Slash Office")
        alert.informativeText = String(localized: "The new language is used after the next launch.")
        alert.runModal()
        return false
    }
}
