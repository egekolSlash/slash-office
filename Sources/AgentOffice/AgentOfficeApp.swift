import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` ile bundle'sız çalışırken Dock'ta görünmesi ve klavye odağı alması için.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        if Notifier.canNotify {
            UNUserNotificationCenter.current().delegate = self
            Notifier.requestAuthorization()
        }
        model.start()
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
        Window("Agent Office", id: "main") {
            ContentView(model: delegate.model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandMenu("Ajanlar") {
                Button("Yeni Claude oturumu") { delegate.model.chooseFolderAndStart(.claude) }
                    .keyboardShortcut("n")
                Button("Yeni terminal") { delegate.model.chooseFolderAndStart(.shell) }
                    .keyboardShortcut("t")
                Divider()
                Button("Ofis") { delegate.model.mode = .office }.keyboardShortcut("1")
                Button("Çalışma") { delegate.model.mode = .work }.keyboardShortcut("2")
                Button("Odak") { delegate.model.mode = .focus }.keyboardShortcut("3")
                Divider()
                Button("Bekleyen ajana atla") { delegate.model.jumpToWaiting() }.keyboardShortcut("j")
                Button("Sonraki terminal") { delegate.model.cycleFocus() }.keyboardShortcut(.tab, modifiers: .control)
                Button("Paneli kapat") {
                    if let id = delegate.model.layout.focused { delegate.model.closePane(id) }
                }
                .keyboardShortcut("w")
            }
        }
    }
}
