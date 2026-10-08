import AgentOfficeCore
import AppKit

/// Uygulamaya özel dil ayarı ve yeniden başlatma (dil ancak yeniden açılışta geçerli olur).
@MainActor
enum AppRestart {
    /// Uygulamanın kendi ayarındaki dil (genel sistem listesi değil).
    static var language: AppLanguage { AppLanguage.stored(in: .standard, domain: Bundle.main.bundleIdentifier) }

    static func apply(_ language: AppLanguage) { language.store(in: .standard) }

    /// Bu açılışın dili (AppDelegate açılışta okur; sonraki seçimler yeniden başlatınca geçerli olur).
    static let launchedLanguage = language

    /// Yeniden başlatma onaylandı: çıkışta ikinci kez sorulmaz, çıkış kesinleşince yeniden açıcı başlar.
    private(set) static var relaunchConfirmed = false

    /// Çalışan ajan varsa önce sorar; onaylanırsa uygulama kapanınca yenisi açılır (`startRelauncherIfConfirmed`,
    /// `applicationWillTerminate`'te). `false`: bu kopya bir paket değil, yeniden açılamaz.
    /// `confirmed`: kullanıcı onayladı, uygulama kapanmak üzere (iptal edilirse çağrılmaz).
    @discardableResult
    static func relaunch(runningAgents: Int, confirmed: () -> Void = {}) -> Bool {
        if runningAgents > 0 {
            let alert = NSAlert()
            alert.messageText = String(localized: "Restart Slash Office?")
            alert.informativeText = String(localized: "Running agents will be stopped. You can resume them after the restart.")
            alert.addButton(withTitle: String(localized: "Restart"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return true }
        }
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return fail() }
        relaunchConfirmed = true
        confirmed()
        NSApp.terminate(nil)
        return true
    }

    /// Çıkış kesinleşti: yeni kopya bu süreç bitince açılır (önce açılırsa hook sunucusu çakışır).
    static func startRelauncherIfConfirmed() {
        guard QuitPolicy.startsRelauncher(relaunchConfirmed: relaunchConfirmed) else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
    }

    private static func fail() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Please restart Slash Office")
        alert.informativeText = String(localized: "The new language is used after the next launch.")
        alert.runModal()
        return false
    }
}
