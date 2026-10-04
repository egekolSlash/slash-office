import AgentOfficeCore
import AppKit
import Foundation
import Observation
import SwiftTerm

@MainActor
@Observable
final class AppModel {
    let store = AgentStore()
    var selectedID: String?
    var errorMessage: String?
    @ObservationIgnored private(set) var terminals: [String: LocalProcessTerminalView] = [:]
    @ObservationIgnored private var coordinators: [String: TerminalCoordinator] = [:]
    @ObservationIgnored private var server: HookServer?

    let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AgentOffice", isDirectory: true)
    }()
    var socketPath: String { supportDirectory.appendingPathComponent("hook.sock").path }

    /// `swift build` hook ikilisini uygulamanın yanına koyar.
    var hookBinaryPath: String {
        Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("agent-office-hook").path
    }

    func start() {
        do {
            try FileManager.default.createDirectory(at: supportDirectory.appendingPathComponent("sessions"), withIntermediateDirectories: true)
            let server = HookServer(socketPath: socketPath) { [weak self] envelope in
                // FIFO: olaylar geliş sırasıyla ana aktöre aktarılır.
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(envelope) } }
            }
            try server.start()
            self.server = server
        } catch {
            errorMessage = "Hook sunucusu başlatılamadı: \(error)"
        }
    }

    func stop() {
        terminals.values.forEach { $0.terminate() }
        server?.stop()
    }

    private func handle(_ envelope: HookEnvelope) {
        guard envelope.provider == "claude" else { return }
        store.apply(ClaudeNormalizer.events(from: envelope.payload), to: envelope.session)
    }

    func newClaudeSession(cwd: URL) {
        let env = ProcessInfo.processInfo.environment
        let dirs = ExecutableLocator.defaultDirectories(home: NSHomeDirectory(), pathVariable: env["PATH"])
        guard let claude = ExecutableLocator.find("claude", searchDirectories: dirs) else {
            errorMessage = "`claude` bulunamadı. Aranan dizinler: \(dirs.joined(separator: ", "))"
            return
        }
        let id = UUID().uuidString.lowercased()
        let settingsURL = supportDirectory.appendingPathComponent("sessions/\(id).settings.json")
        let hookCommand = "\(ClaudeLaunch.shellQuote(hookBinaryPath)) claude"
        do {
            try ClaudeLaunch.settingsJSON(hookCommand: hookCommand).write(to: settingsURL)
        } catch {
            errorMessage = "Ayar dosyası yazılamadı: \(error)"
            return
        }
        let command = ClaudeLaunch.command(claudePath: claude, sessionID: id, resume: false, settingsPath: settingsURL.path,
                                           cwd: cwd.path, socketPath: socketPath, baseEnvironment: env)
        store.register(id: id, title: cwd.lastPathComponent, cwd: cwd.path)

        let terminal = LocalProcessTerminalView(frame: .init(x: 0, y: 0, width: 800, height: 600))
        let coordinator = TerminalCoordinator(sessionID: id) { [weak self] id in self?.store.markExited(id) }
        terminal.processDelegate = coordinator
        terminals[id] = terminal
        coordinators[id] = coordinator
        terminal.startProcess(executable: command.executable, args: command.args,
                              environment: command.environmentList, currentDirectory: command.currentDirectory)
        selectedID = id
    }

    func chooseFolderAndStart() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Ajanı başlat"
        if panel.runModal() == .OK, let url = panel.url { newClaudeSession(cwd: url) }
    }
}

final class TerminalCoordinator: LocalProcessTerminalViewDelegate {
    let sessionID: String
    let onExit: @MainActor (String) -> Void

    init(sessionID: String, onExit: @escaping @MainActor (String) -> Void) {
        self.sessionID = sessionID
        self.onExit = onExit
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        let id = sessionID, onExit = onExit
        DispatchQueue.main.async { MainActor.assumeIsolated { onExit(id) } }
    }
}
