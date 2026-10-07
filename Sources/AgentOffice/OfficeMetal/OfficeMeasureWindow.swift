import AgentOfficeCore
import AppKit
import SwiftUI
import Synchronization

/// `AgentOffice --office-window [--mini] [--walk] [--seconds <n>]`: demo ofisini yüzen (tüm Space'lerde görünen)
/// bir pencerede gösterir ve her 2 sn'de kare hızını ve süreç CPU'sunu yazar (spec v4 §6 ölçümü). `--walk`: bir köylü
/// 4 sn'de bir bekleme ile çalışma arasında gidip gelir (native kare hızını ölçmek için). Hook sunucusu başlamaz.
@MainActor
enum OfficeMeasureWindow {
    nonisolated static let frames = Atomic<Int>(0)

    static func requested(_ arguments: [String]) -> Bool { arguments.contains("--office-window") }

    static func run(arguments: [String], model: AppModel) {
        setvbuf(stdout, nil, _IONBF, 0)
        NSApplication.shared.setActivationPolicy(.accessory)
        model.loadDemoSessions()
        let mini = arguments.contains("--mini")
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: mini ? 420 : 1200, height: mini ? 280 : 800),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Ofis ölçümü" + (mini ? " (mini)" : "")
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OfficeView(model: model, interactive: !mini))
        window.orderFrontRegardless()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in exit(0) }

        if arguments.contains("--walk") {
            var waiting = false
            Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
                MainActor.assumeIsolated {
                    waiting.toggle()
                    model.store.setState(waiting ? .waiting(.question("?")) : .working(tool: "Edit"), for: "demo-0")
                }
            }
        }
        if let i = arguments.firstIndex(of: "--seconds"), let seconds = Double(arguments[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
        }
        var lastTime = CACurrentMediaTime(), lastCPU = processCPU(), lastFrames = 0
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            let now = CACurrentMediaTime(), cpu = processCPU(), count = frames.load(ordering: .relaxed)
            print(String(format: "fps=%.1f  süreç CPU=%%%.1f", Double(count - lastFrames) / (now - lastTime),
                         (cpu - lastCPU) / (now - lastTime) * 100))
            lastTime = now; lastCPU = cpu; lastFrames = count
        }
    }

    /// Sürecin toplam CPU süresi (kullanıcı + sistem, sn).
    static func processCPU() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }
}
