import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` ile bundle'sız çalışırken Dock'ta görünmesi ve klavye odağı alması için.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
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
                Button("Yeni Claude oturumu") { delegate.model.chooseFolderAndStart() }
                    .keyboardShortcut("n")
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
