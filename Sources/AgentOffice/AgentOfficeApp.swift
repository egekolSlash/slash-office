import AgentOfficeCore
import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `--office-snapshot <png>`: demo ofisini ekran dışı çizip çık (hook sunucusu ve oturumlar başlamaz).
        if OfficeSnapshot.requested(CommandLine.arguments) {
            let model = self.model
            Task { @MainActor in await OfficeSnapshot.run(arguments: CommandLine.arguments, model: model) }
            return
        }
        if OnboardingView.snapshot(arguments: CommandLine.arguments, model: model) { exit(0) }
        // `--office-window`: demo ofisini yüzen pencerede gösterip kare hızı ve CPU ölçer.
        if OfficeMeasureWindow.requested(CommandLine.arguments) {
            OfficeMeasureWindow.run(arguments: CommandLine.arguments, model: model)
            return
        }
        // `swift run` ile bundle'sız çalışırken Dock'ta görünmesi ve klavye odağı alması için.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        // Bildirim izni ilk açılıştaki izin ekranında istenir.
        if Notifier.canNotify { UNUserNotificationCenter.current().delegate = self }
        model.start()
        // Shift'siz ⌘= de yazıyı büyütsün (ABD klavyesinde + Shift ister; menüde ⌘+ görünür).
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [model] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "=" else { return event }
            MainActor.assumeIsolated { model.zoom(by: 1) }
            return nil
        }
        // Uygulamaya dönünce odaktaki oturumun "bitti, görülmedi" işareti kalkar.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [model] _ in
            MainActor.assumeIsolated { model.markFocusedSeen() }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.hasActiveAgents else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Çalışan ajanlar var"
        alert.informativeText = "Çıkarsan çalışan ve cevap bekleyen ajanların süreçleri kapanır. Oturumlar sonra kaldığı yerden devam ettirilebilir."
        alert.addButton(withTitle: "Çık")
        alert.addButton(withTitle: "Vazgeç")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["sessionID"] as? String else { return }
        await MainActor.run {
            NSApplication.shared.activate()
            model.showTerminal(id)
        }
    }
}

@main
struct AgentOfficeApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        // Tek pencere: pencereyi kapatıp açmak yeni model ya da ikinci hook sunucusu oluşturmaz.
        Window("Slash Office", id: "main") {
            ContentView(model: delegate.model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandMenu("Agents") {
                let model = delegate.model
                let title = { (id: String) in LocalizedStringKey(ShortcutCatalog.shortcut(id).title) }
                Button(title("session.newClaude")) { model.openLauncher(beside: false, claude: true) }.shortcut("session.newClaude")
                Button(title("pane.new")) { model.openLauncher(beside: false) }.shortcut("pane.new")
                Button(title("pane.newBeside")) { model.openLauncher(beside: true) }.shortcut("pane.newBeside")
                Button("Permissions…") { model.showPermissions = true }
                Divider()
                Button(title("mode.office")) { model.mode = .office }.shortcut("mode.office")
                Button(title("mode.work")) { model.mode = .work }.shortcut("mode.work")
                Button(title("mode.focus")) { model.mode = .focus }.shortcut("mode.focus")
                Divider()
                Button(title("text.bigger")) { model.zoom(by: 1) }.shortcut("text.bigger")
                Button(title("text.smaller")) { model.zoom(by: -1) }.shortcut("text.smaller")
                Button(title("text.actual")) { model.resetZoom() }.shortcut("text.actual")
                Divider()
                Button(title("session.jumpToWaiting")) { model.jumpToWaiting() }.shortcut("session.jumpToWaiting")
                Button(title("session.previous")) { model.showAdjacentSession(-1) }.shortcut("session.previous")
                Button(title("session.next")) { model.showAdjacentSession(1) }.shortcut("session.next")
                Button(title("pane.previous")) { model.cycleFocus(backward: true) }.shortcut("pane.previous")
                Button(title("pane.next")) { model.cycleFocus() }.shortcut("pane.next")
                Button(title("session.resume")) { model.resumeFocused() }.shortcut("session.resume")
                Button(title("session.removeStopped")) { model.removeFocusedStopped() }.shortcut("session.removeStopped")
                Button(title("session.resumeAll")) { model.resumeAllStopped() }.shortcut("session.resumeAll")
                Divider()
                Button(title("pane.close")) {
                    if let id = model.layout.focused { model.closePane(id) }
                }
                .shortcut("pane.close")
            }
            CommandGroup(replacing: .help) {
                Button("Welcome Guide…") { delegate.model.openOnboarding() }
            }
        }
        Settings { SettingsView(runningAgents: { [delegate] in delegate.model.runningAgentCount }) }
    }
}
