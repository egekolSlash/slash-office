import AgentOfficeCore
import AppKit
import Foundation
import Observation
import SwiftTerm

@MainActor
@Observable
final class AppModel {
    let store = AgentStore()
    var layout = TerminalLayout()
    var mode: WorkspaceMode = .work
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

    @ObservationIgnored private var records: [String: SessionRecord] = [:]
    /// Kullanıcının shell'indeki PATH (`.zshrc` dahil); npm/nvm/bun ile kurulan claude ve node için gerekli.
    @ObservationIgnored private lazy var launchPATH: String? = {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return ShellPath.capture(shell: shell, timeout: 3) ?? ProcessInfo.processInfo.environment["PATH"]
    }()
    var recordsURL: URL { supportDirectory.appendingPathComponent("sessions.json") }
    let claudeProjectsDirectory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")

    func start() {
        guard server == nil else { return }
        do {
            try FileManager.default.createDirectory(at: supportDirectory.appendingPathComponent("sessions"), withIntermediateDirectories: true)
            let server = HookServer(socketPath: socketPath) { [weak self] envelope in
                // FIFO: olaylar geliş sırasıyla ana aktöre aktarılır.
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(envelope) } }
            }
            try server.start()
            self.server = server
        } catch HookServerError.alreadyRunning {
            errorMessage = "Agent Office zaten açık. Durumlar diğer pencerede güncelleniyor; bu kopyayı kapat."
        } catch {
            errorMessage = "Hook sunucusu başlatılamadı: \(error)"
        }
        // Önceki oturumlar durmuş olarak geri gelir; her claude süreci ayrı bellek tuttuğu için otomatik başlatılmaz.
        for record in SessionStore.load(from: recordsURL).sorted(by: { $0.createdAt < $1.createdAt }) {
            records[record.id] = record
            store.register(id: record.id, title: record.title, cwd: record.cwd, state: .exited)
        }
        if let first = store.sessions.first?.id { layout.show(first) }
    }

    func stop() {
        terminals.values.forEach { $0.terminate() }
        server?.stop()
    }

    private func handle(_ envelope: HookEnvelope) {
        guard envelope.provider == "claude" else { return }
        store.apply(ClaudeNormalizer.events(from: envelope.payload), to: envelope.session)
        // /clear sonrası Claude'un oturum kimliği değişir; resume için en sonuncusunu sakla.
        if let claudeID = store.session(envelope.session)?.providerSessionID,
           var record = records[envelope.session], record.claudeSessionID != claudeID {
            record.noteClaudeSession(claudeID)
            records[envelope.session] = record
            saveRecords()
        }
    }

    private func saveRecords() {
        do {
            try SessionStore.save(Array(records.values), to: recordsURL)
        } catch {
            errorMessage = "Oturum listesi kaydedilemedi: \(error)"
        }
    }

    private func settingsURL(for id: String) -> URL {
        supportDirectory.appendingPathComponent("sessions/\(id).settings.json")
    }

    func newClaudeSession(cwd: URL) {
        let id = UUID().uuidString.lowercased()
        let record = SessionRecord(id: id, title: cwd.lastPathComponent, cwd: cwd.path, claudeSessionID: id, createdAt: .now)
        guard launch(record: record, claudeSessionID: id, resume: false) else { return }
        records[id] = record
        saveRecords()
        store.register(id: id, title: record.title, cwd: record.cwd)
        showTerminal(id)
    }

    /// Kapanmış oturumu kaldığı yerden açar. Hiç mesaj yazılmamışsa (transcript yok) aynı kimlikle sıfırdan başlar.
    func resume(_ id: String) {
        guard var record = records[id] else { return }
        guard FileManager.default.fileExists(atPath: record.cwd) else {
            errorMessage = "Proje klasörü bulunamadı: \(record.cwd)\nKlasör taşındıysa oturumu kaldırıp yeniden aç."
            return
        }
        // Süreç hâlâ çalışıyorsa yeni terminal açmak eskisini (ve içindeki claude'u) öldürür.
        if terminals[id]?.process.running == true {
            store.restart(id)
            return
        }
        let projects = claudeProjectsDirectory
        let plan = ResumePlan.decide(candidates: record.resumeCandidates,
                                     transcriptExists: { ClaudeTranscript.exists(sessionID: $0, projectsDirectory: projects) },
                                     freshID: { UUID().uuidString.lowercased() })
        guard launch(record: record, claudeSessionID: plan.claudeSessionID, resume: plan.resume) else { return }
        record.noteClaudeSession(plan.claudeSessionID)
        records[id] = record
        saveRecords()
        store.restart(id)
        showTerminal(id)
    }

    /// Terminal var ve süreci kapanmışsa true: çıktısı (ör. hata mesajı) görünür kalsın diye terminal gösterilir.
    func hasEndedTerminal(_ id: String) -> Bool {
        guard let terminal = terminals[id] else { return false }
        return !terminal.process.running
    }

    func isRunning(_ id: String) -> Bool {
        terminals[id]?.process.running == true
    }

    func remove(_ id: String) {
        terminals[id]?.terminate()
        terminals[id] = nil
        coordinators[id] = nil
        records[id] = nil
        store.remove(id)
        try? FileManager.default.removeItem(at: settingsURL(for: id))
        saveRecords()
        layout.close(id)
    }

    @discardableResult
    private func launch(record: SessionRecord, claudeSessionID: String, resume: Bool) -> Bool {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = launchPATH
        let dirs = ExecutableLocator.defaultDirectories(home: NSHomeDirectory(), pathVariable: launchPATH)
        guard let claude = ExecutableLocator.find("claude", searchDirectories: dirs) else {
            errorMessage = "`claude` bulunamadı. Aranan dizinler: \(dirs.joined(separator: ", "))"
            return false
        }
        guard FileManager.default.isExecutableFile(atPath: hookBinaryPath) else {
            errorMessage = "Hook yardımcısı bulunamadı: \(hookBinaryPath)\nÖnce `swift build` çalıştır (sadece `swift run AgentOffice` onu derlemez)."
            return false
        }
        let settings = settingsURL(for: record.id)
        let hookCommand = "\(ClaudeLaunch.shellQuote(hookBinaryPath)) claude"
        do {
            try ClaudeLaunch.settingsJSON(hookCommand: hookCommand).write(to: settings)
        } catch {
            errorMessage = "Ayar dosyası yazılamadı: \(error)"
            return false
        }
        let command = ClaudeLaunch.command(claudePath: claude, sessionID: claudeSessionID, resume: resume,
                                           settingsPath: settings.path, cwd: record.cwd, socketPath: socketPath,
                                           baseEnvironment: env, tag: record.id)
        let terminal = LocalProcessTerminalView(frame: .init(x: 0, y: 0, width: 800, height: 600))
        let coordinator = TerminalCoordinator(sessionID: record.id) { [weak self] id in self?.store.markExited(id) }
        terminal.processDelegate = coordinator
        terminals[record.id] = terminal
        coordinators[record.id] = coordinator
        terminal.startProcess(executable: command.executable, args: command.args,
                              environment: command.environmentList, currentDirectory: command.currentDirectory)
        return true
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

enum WorkspaceMode: Equatable {
    case office, work, focus
}

extension AppModel {
    func showTerminal(_ id: String) {
        layout.show(id)
        if mode == .office { mode = .work }
        focusTerminalView()
    }

    func addTerminal(_ id: String) {
        layout.add(id)
        if mode == .office { mode = .work }
        focusTerminalView()
    }

    func closePane(_ id: String) {
        layout.close(id)
        focusTerminalView()
    }

    func cycleFocus() {
        layout.cycle()
        focusTerminalView()
    }

    func jumpToWaiting() {
        let ids = store.sessions.map(\.id)
        let next = WaitingNavigator.next(after: layout.focused, ids: ids) { id in
            if case .waiting = self.store.session(id)?.state { true } else { false }
        }
        if let next { showTerminal(next) }
    }

    /// Odaktaki terminalin klavyeyi alması için.
    func focusTerminalView() {
        guard let id = layout.focused, let terminal = terminals[id] else { return }
        DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) }
    }
}
