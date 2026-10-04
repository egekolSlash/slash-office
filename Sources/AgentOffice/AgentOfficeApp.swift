import AppKit
import SwiftUI

@main
struct AgentOfficeApp: App {
    @State private var model = AppModel()

    init() {
        // `swift run` ile bundle'sız çalışırken Dock'ta görünmesi ve klavye odağı alması için.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup("Agent Office") {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear { model.start() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.stop()
                }
        }
    }
}
