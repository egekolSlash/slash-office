import AgentOfficeCore
import AppKit
import Foundation
import Observation
import SwiftTerm

@MainActor
@Observable
final class AppModel {
    let store = AgentStore()
    /// Ofis modu ve mini ofisin kameraları: mod değişince yer ve yakınlık korunur.
    let officeCamera = OfficeCamera()
    let miniOfficeCamera = OfficeCamera()
    let diffWatcher = DiffWatcher()
    var changesScope: ChangesScope = .uncommitted
    var layout = TerminalLayout()
    var mode: WorkspaceMode = .work { didSet { markFocusedSeen() } }
    var errorMessage: String?
    /// İzin ekranı ilk açılışta bir kez gösterilir; sonra Ajanlar > İzinler… ile açılır.
    var showPermissions = !UserDefaults.standard.bool(forKey: "permissionsShown")
    /// "Yeni" panelde gösterilen son projeler (en yenisi başta).
    private(set) var recentProjects: [String] = UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []
    /// Ghostty'nin config'i ve teması; uygulama açılırken okunur.
    private(set) var appearance = GhosttyConfig.load()
    /// ⌘= / ⌘- ile değişir, tüm terminallere uygulanır ve hatırlanır; ⌘0 Ghostty'deki boyuta döner.
    var terminalFontSize: Double = UserDefaults.standard.object(forKey: "terminalFontSize") as? Double ?? GhosttyConfig.load().fontSize {
        didSet {
            UserDefaults.standard.set(terminalFontSize, forKey: "terminalFontSize")
            for terminal in terminals.values { terminal.apply(appearance, fontSize: terminalFontSize) }
        }
    }
    /// Proje klasörü → ikon (resim ya da proje türü sembolü); arka planda bir kez bulunur.
    private(set) var projectIcons: [String: LoadedProjectIcon] = [:]
    /// Proje klasörü → oda anahtarı (ana depo; worktree'ler aynı odada) ve worktree adı. Arka planda bir kez bulunur.
    private(set) var roomIdentities: [String: RepoIdentity.Identity] = [:]
    @ObservationIgnored private var roomKeyLookups: Set<String> = []
    /// Masa yerleri: oturum kalkınca diğerleri yer değiştirmesin diye hatırlanır (spec §3).
    @ObservationIgnored private var deskSlots: [String: OfficePlan.DeskSlot] = [:]
    /// Odaların sırası: proje ofise ilk girdiğinde sona eklenir, odası boşalınca çıkar.
    @ObservationIgnored private var roomOrder: [String] = []
    /// ⌘J ofis modunda: kamera bu masaya gider (OfficeView okuyup sıfırlar).
    var officeFocusRequest: String?
    /// Kullanıcının değiştirdiği köylü görünüşleri ve oda stilleri (değiştirilmeyenler varsayılan).
    var avatarLooks: [String: AvatarLook] = [:]
    var roomStyles: [String: RoomStyle] = [:]
    /// "Görünümü düzenle…" / "Odayı düzenle…" sayfaları.
    var editingAvatar: String?
    var editingRoom: String?
    @ObservationIgnored private var iconLookups: Set<String> = []
    @ObservationIgnored private(set) var terminals: [String: AgentTerminalView] = [:]
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

    @ObservationIgnored private var shellTimer: Timer?
    /// Oturum başına son başlık okuma zamanı: kayıt dosyası en fazla 5 sn'de bir okunur.
    @ObservationIgnored private var titleReads: [String: Date] = [:]
    /// İçinde hook gönderen bir claude çalışan shell oturumları.
    @ObservationIgnored private var shellsWithClaudeHooks: Set<String> = []

    func start() {
        guard server == nil else { return }
        shellTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollShells() }
        }
        do {
            try FileManager.default.createDirectory(at: supportDirectory.appendingPathComponent("sessions"), withIntermediateDirectories: true)
            let server = HookServer(socketPath: socketPath) { [weak self] envelope in
                // FIFO: olaylar geliş sırasıyla ana aktöre aktarılır.
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(envelope) } }
            }
            try server.start()
            self.server = server
        } catch HookServerError.alreadyRunning {
            errorMessage = "Slash Office zaten açık. Durumlar diğer pencerede güncelleniyor; bu kopyayı kapat."
        } catch {
            errorMessage = "Hook sunucusu başlatılamadı: \(error)"
        }
        if ProcessInfo.processInfo.environment["AGENT_OFFICE_DEMO"] == "1" {
            loadDemoSessions()
            return
        }
        avatarLooks = StyleStore<AvatarLook>.load(from: avatarsURL)
        roomStyles = StyleStore<RoomStyle>.load(from: roomStylesURL)
        // Önceki oturumlar durmuş olarak geri gelir; her claude süreci ayrı bellek tuttuğu için otomatik başlatılmaz.
        for record in SessionStore.load(from: recordsURL).sorted(by: { $0.createdAt < $1.createdAt }) {
            records[record.id] = record
            store.register(id: record.id, title: record.title, cwd: record.cwd, state: .exited)
            store.setWorkTitle(record.workTitle, for: record.id)
        }
        if let first = store.sessions.first?.id { layout.show(first) }
        // Kayıtlı oturumların klasörleri de son projelere girer (eskisi sona).
        for record in records.values.sorted(by: { $0.createdAt < $1.createdAt }) where record.cwd != NSHomeDirectory() {
            if !recentProjects.contains(record.cwd) { recentProjects.append(record.cwd) }
        }
    }

    func stop() {
        terminals.values.forEach { $0.terminate() }
        server?.stop()
    }

    private func handle(_ envelope: HookEnvelope) {
        guard envelope.provider == "claude" else { return }
        let wasWaiting: Bool = if case .waiting = store.session(envelope.session)?.state { true } else { false }
        var events = ClaudeNormalizer.events(from: envelope.payload)
        if kind(of: envelope.session) == .shell {
            // Claude kapanınca terminal açık kalır: durumu yine shell yoklaması belirler.
            events.removeAll { if case .sessionEnded = $0 { true } else { false } }
            if !events.isEmpty { shellsWithClaudeHooks.insert(envelope.session) }
        }
        store.apply(events, to: envelope.session, watched: isWatched(envelope.session))
        if let path = ClaudeNormalizer.transcriptPath(from: envelope.payload) { refreshWorkTitle(envelope.session, transcript: path) }
        if let session = store.session(envelope.session), case .waiting(let reason) = session.state, !wasWaiting {
            Notifier.notifyWaiting(sessionID: session.id, title: session.title, reason: reason)
        }
        Notifier.updateBadge(waiting: store.waitingCount)
        // /clear sonrası Claude'un oturum kimliği değişir; resume için en sonuncusunu sakla.
        if let claudeID = store.session(envelope.session)?.providerSessionID,
           var record = records[envelope.session], record.kind == .claude, record.claudeSessionID != claudeID {
            record.noteClaudeSession(claudeID)
            records[envelope.session] = record
            saveRecords()
        }
        if events.contains(where: { if case .promptSubmitted = $0 { true } else { false } }) {
            takeTurnSnapshot(envelope.session)
        }
        if events.contains(where: Self.changesFiles) { diffChanged(envelope.session) }
    }

    /// Dosyaya dokunmuş olabilecek olaylar: dosya yazan tool'lar, Bash ve tur sonu.
    private static func changesFiles(_ event: AgentEvent) -> Bool {
        switch event {
        case .toolFinished(let name, let files): !files.isEmpty || ["Edit", "Write", "MultiEdit", "NotebookEdit", "Bash"].contains(name)
        case .turnEnded: true
        default: false
        }
    }

    /// Odaktaki oturumun diff'i yenilenir; diğerleri eskidi olarak işaretlenir, odağa gelince yenilenir.
    func diffChanged(_ id: String) {
        if id == layout.focused { requestDiff(id) } else { diffWatcher.markStale(id) }
    }

    func requestDiff(_ id: String, immediately: Bool = false) {
        guard let record = records[id] else { return }
        diffWatcher.refresh(id: id, scope: changesScope, cwd: record.cwd, baseline: record.baseline,
                            turnTree: record.turnTree, delay: immediately ? .zero : .milliseconds(500))
    }

    /// Oturumun başlangıç commit'ini arka planda okuyup kaydeder (git ana thread'de çalışmaz).
    private func captureBaseline(_ id: String, cwd: String) {
        Task { [weak self] in
            let head = await Task.detached(priority: .utility) { GitWorkspace(directory: cwd).head() }.value
            guard let self, let head, var record = self.records[id], record.baseline == nil else { return }
            record.baseline = head
            self.records[id] = record
            self.saveRecords()
        }
    }

    /// Kullanıcının isteği (ya da shell'de komut) başlarken çalışma alanının fotoğrafı: "Son tur" diff'i buna göre.
    func takeTurnSnapshot(_ id: String) {
        guard let cwd = records[id]?.cwd else { return }
        Task { [weak self] in
            let tree = await Task.detached(priority: .userInitiated) { GitWorkspace(directory: cwd).snapshotTree() }.value
            guard let self, let tree, var record = self.records[id] else { return }
            record.turnTree = tree
            self.records[id] = record
            self.saveRecords()
            DebugLog.write("turn snapshot \(id): \(tree)")
            self.diffChanged(id)
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

    /// `replacing`: oturum bu paneli ("yeni" panel) yerinde doldurur; yoksa odaktaki panelde açılır.
    func newClaudeSession(cwd: URL, replacing: String? = nil) {
        let id = UUID().uuidString.lowercased()
        let record = SessionRecord(id: id, title: cwd.lastPathComponent, cwd: cwd.path, claudeSessionID: id, createdAt: .now)
        guard launch(record: record, claudeSessionID: id, resume: false) else { return }
        records[id] = record
        saveRecords()
        store.register(id: id, title: record.title, cwd: record.cwd)
        captureBaseline(id, cwd: record.cwd)
        noteRecentProject(record.cwd)
        present(id, replacing: replacing)
    }

    func newShellSession(cwd: URL, replacing: String? = nil) {
        let id = UUID().uuidString.lowercased()
        let title = cwd.path == NSHomeDirectory() ? "~" : cwd.lastPathComponent
        let record = SessionRecord(id: id, title: title, cwd: cwd.path, claudeSessionID: nil, createdAt: .now, kind: .shell)
        guard launchShell(record: record) else { return }
        records[id] = record
        saveRecords()
        store.register(id: id, title: record.title, cwd: record.cwd, state: .idle)
        captureBaseline(id, cwd: record.cwd)
        if record.cwd != NSHomeDirectory() { noteRecentProject(record.cwd) }
        present(id, replacing: replacing)
    }

    private func present(_ id: String, replacing launcher: String?) {
        guard let launcher, layout.visible.contains(launcher) else { showTerminal(id); return }
        layout.replace(launcher, with: id)
        if mode == .office { mode = .work }
        focusTerminalView()
    }

    func kind(of id: String) -> SessionKind {
        records[id]?.kind ?? .claude
    }

    /// Kapanmış oturumu kaldığı yerden açar. Hiç mesaj yazılmamışsa (transcript yok) aynı kimlikle sıfırdan başlar.
    /// Shell oturumu aynı klasörde yeni bir shell olarak açılır.
    /// `show: false`: terminal açılır ama panel düzeni değişmez (toplu devam ettirme).
    func resume(_ id: String, show: Bool = true) {
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
        if record.kind == .shell {
            guard launchShell(record: record) else { return }
            store.restart(id)
            store.setState(.idle, for: id)
            if show { showTerminal(id) }
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
        if show { showTerminal(id) }
    }

    /// Durmuş (süreci çalışmayan) oturumlar, liste sırasıyla.
    var stoppedSessionIDs: [String] {
        store.sessions.filter { $0.state == .exited && !isRunning($0.id) }.map(\.id)
    }

    func isStopped(_ id: String) -> Bool { store.session(id)?.state == .exited && !isRunning(id) }

    /// ⌘⇧R: bütün durmuş oturumları devam ettirir; panel düzeni korunur.
    func resumeAllStopped() {
        for id in stoppedSessionIDs { resume(id, show: false) }
        focusTerminalView()
    }

    /// ⌘R: odaktaki durmuş oturumu devam ettirir.
    func resumeFocused() {
        if let id = layout.focused, isStopped(id) { resume(id) }
    }

    /// ⌘⇧⌫: odaktaki durmuş oturumu kaldırır (süreç çalışmadığı için onay gerekmez).
    func removeFocusedStopped() {
        if let id = layout.focused, isStopped(id) { remove(id) }
    }

    /// Terminal var ve süreci kapanmışsa true: çıktısı (ör. hata mesajı) görünür kalsın diye terminal gösterilir.
    func hasEndedTerminal(_ id: String) -> Bool {
        guard let terminal = terminals[id] else { return false }
        return !terminal.process.running
    }

    /// Çıkışta onay istenmesi gereken (çalışan ya da cevap bekleyen) ajan var mı?
    var hasActiveAgents: Bool {
        store.sessions.contains { session in
            switch session.state {
            case .working, .waiting: isRunning(session.id)
            default: false
            }
        }
    }

    func isRunning(_ id: String) -> Bool {
        terminals[id]?.process.running == true
    }

    /// `keepListFocus`: listeden silinince klavye listede kalır ve seçim komşu oturuma geçer (art arda ⌘⌫ için).
    func remove(_ id: String, keepListFocus: Bool = false) {
        let order = store.sessions.map(\.id)
        let neighbor = order.firstIndex(of: id).flatMap { index in
            index + 1 < order.count ? order[index + 1] : (index > 0 ? order[index - 1] : nil)
        }
        terminals[id]?.terminate()
        terminals[id] = nil
        coordinators[id] = nil
        records[id] = nil
        if avatarLooks[id] != nil { setLook(nil, for: id) }
        store.remove(id)
        try? FileManager.default.removeItem(at: settingsURL(for: id))
        saveRecords()
        layout.close(id)
        diffWatcher.forget(id)
        Notifier.updateBadge(waiting: store.waitingCount)
        if keepListFocus, let neighbor {
            showTerminal(neighbor, takeKeyboard: false)
        } else {
            focusTerminalView()
        }
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
        guard let settings = writeHookSettings(record.id) else { return false }
        let command = ClaudeLaunch.command(claudePath: claude, sessionID: claudeSessionID, resume: resume,
                                           settingsPath: settings.path, cwd: record.cwd, socketPath: socketPath,
                                           baseEnvironment: env, tag: record.id)
        startTerminal(record: record, command: command)
        return true
    }

    /// Bu oturumun hook'larını ekleyen `--settings` dosyası.
    private func writeHookSettings(_ id: String) -> URL? {
        let settings = settingsURL(for: id)
        let hookCommand = "\(ClaudeLaunch.shellQuote(hookBinaryPath)) claude"
        do {
            try ClaudeLaunch.settingsJSON(hookCommand: hookCommand).write(to: settings)
            return settings
        } catch {
            errorMessage = "Ayar dosyası yazılamadı: \(error)"
            return nil
        }
    }

    /// Düz terminal: kullanıcının login shell'i. Terminalde elle açılan `claude` bir sarmalayıcıyla bu oturumun
    /// hook'larını alır; claude ya da hook yardımcısı yoksa terminal entegrasyonsuz açılır.
    @discardableResult
    private func launchShell(record: SessionRecord) -> Bool {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = launchPATH
        let shell = env["SHELL"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil } ?? "/bin/zsh"
        startTerminal(record: record, command: ShellLaunch.command(shellPath: shell, cwd: record.cwd, sessionID: record.id,
                                                                   baseEnvironment: env, integration: shellIntegration(record.id)))
        return true
    }

    private func shellIntegration(_ id: String) -> ShellIntegration? {
        let dirs = ExecutableLocator.defaultDirectories(home: NSHomeDirectory(), pathVariable: launchPATH)
        guard let claude = ExecutableLocator.find("claude", searchDirectories: dirs),
              FileManager.default.isExecutableFile(atPath: hookBinaryPath),
              let settings = writeHookSettings(id) else { return nil }
        let integration = ShellIntegration(binDirectory: supportDirectory.appendingPathComponent("bin").path,
                                           zdotDirectory: supportDirectory.appendingPathComponent("zdotdir").path,
                                           claudePath: claude, settingsPath: settings.path, socketPath: socketPath)
        do {
            try integration.install()
            return integration
        } catch {
            DebugLog.write("shell integration install failed: \(error)")
            return nil
        }
    }

    private func startTerminal(record: SessionRecord, command: LaunchCommand) {
        let terminal = AgentTerminalView(frame: .init(x: 0, y: 0, width: 800, height: 600))
        terminal.apply(appearance, fontSize: terminalFontSize)
        // Kullanıcı terminale tıklayıp yazmaya başlayınca odak vurgusu o panele geçsin.
        let id = record.id
        terminal.onFocus = { [weak self] in self?.noteKeyboardFocus(id) }
        let coordinator = TerminalCoordinator(sessionID: record.id) { [weak self] id in
            self?.store.markExited(id)
            Notifier.updateBadge(waiting: self?.store.waitingCount ?? 0)
        }
        terminal.processDelegate = coordinator
        terminals[record.id] = terminal
        coordinators[record.id] = coordinator
        terminal.startProcess(executable: command.executable, args: command.args,
                              environment: command.environmentList, currentDirectory: command.currentDirectory)
    }

    func chooseFolderAndStart(_ kind: SessionKind = .claude, replacing: String? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = kind == .shell ? "Terminali aç" : "Ajanı başlat"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch kind {
        case .claude: newClaudeSession(cwd: url, replacing: replacing)
        case .shell: newShellSession(cwd: url, replacing: replacing)
        }
    }

    /// Shell oturumu `cd` ile başka klasöre geçti: ofisteki proje, başlık, ikon ve diff yeni klasöre taşınır.
    private func relocateShell(_ id: String, to cwd: String) {
        guard var record = records[id] else { return }
        let title = cwd == NSHomeDirectory() ? "~" : (cwd as NSString).lastPathComponent
        DebugLog.write("shell \(id) cwd -> \(cwd)")
        record.cwd = cwd
        record.title = title
        record.baseline = nil
        record.turnTree = nil
        records[id] = record
        saveRecords()
        store.relocate(id, cwd: cwd, title: title)
        diffWatcher.forget(id)
        captureBaseline(id, cwd: cwd)
        if cwd != NSHomeDirectory() { noteRecentProject(cwd) }
        diffChanged(id)
    }

    /// Shell oturumlarında hook yok: ön plandaki komut saniyede bir okunur.
    func pollShells() {
        for (id, record) in records where record.kind == .shell {
            guard let terminal = terminals[id], terminal.process.running else { continue }
            let pid = terminal.process.shellPid
            let group = ShellActivity.foregroundGroup(ptyFD: terminal.process.childfd)
            // Ön planda bir program (ör. başka projede açılan claude) varsa onun klasörü, yoksa shell'inki.
            let foregroundPID = group.flatMap { $0 != pid ? $0 : nil }
            if let cwd = foregroundPID.flatMap(ShellActivity.workingDirectory) ?? ShellActivity.workingDirectory(pid),
               cwd != record.cwd {
                relocateShell(id, to: cwd)
            }
            let command = group.flatMap(ShellActivity.processName)
            let state = ShellActivity.state(shellPID: pid, foregroundGroup: group, commandName: command)
            let previous = store.session(id)?.state
            // Terminalde açılan claude hook gönderiyorsa durumu (çalışıyor, soru soruyor, boşta) hook belirler.
            if command == "claude", shellsWithClaudeHooks.contains(id) { continue }
            shellsWithClaudeHooks.remove(id)
            if previous != state { DebugLog.write("shell \(id) -> \(state)") }
            store.setState(state, for: id, watched: isWatched(id))
            if case .working = previous, state == .idle { diffChanged(id) }
            if previous == .idle, case .working = state { takeTurnSnapshot(id) }
        }
    }
}

extension AppModel {
    /// Henüz bakılmamış klasörlerin oda anahtarını arka planda bulur (git ana thread'de çalışmaz).
    func loadRoomKeys(_ directories: [String]) {
        for directory in directories where !roomKeyLookups.contains(directory) {
            roomKeyLookups.insert(directory)
            Task { [weak self] in
                let identity = await Task.detached(priority: .utility) { RepoIdentity.locate(directory) }.value
                self?.roomIdentities[directory] = identity
            }
        }
    }

    func roomKey(for cwd: String) -> String { roomIdentities[cwd]?.roomKey ?? cwd }

    func look(for id: String) -> AvatarLook { avatarLooks[id] ?? AvatarLook.default(for: id) }

    func style(for roomKey: String) -> RoomStyle { roomStyles[roomKey] ?? RoomStyle.default(for: roomKey) }

    var avatarsURL: URL { supportDirectory.appendingPathComponent("avatars.json") }
    var roomStylesURL: URL { supportDirectory.appendingPathComponent("rooms.json") }

    /// Varsayılandan farklıysa saklanır; `nil` ya da varsayılan görünüş kaydı siler.
    func setLook(_ look: AvatarLook?, for id: String) {
        avatarLooks[id] = look == AvatarLook.default(for: id) ? nil : look
        do { try StyleStore.save(avatarLooks, to: avatarsURL) } catch { errorMessage = "Görünüş kaydedilemedi: \(error)" }
    }

    func setStyle(_ style: RoomStyle?, for roomKey: String) {
        roomStyles[roomKey] = style == RoomStyle.default(for: roomKey) ? nil : style
        do { try StyleStore.save(roomStyles, to: roomStylesURL) } catch { errorMessage = "Oda stili kaydedilemedi: \(error)" }
    }

    func worktree(for cwd: String) -> String? { roomIdentities[cwd]?.worktree }

    /// Ofisin kat planı; masa yerleri önceki plandan korunur.
    func officePlan() -> OfficePlan {
        let members = store.sessions.map { OfficePlan.Member(id: $0.id, roomKey: roomKey(for: $0.cwd)) }
        deskSlots = OfficePlan.assignSlots(members, previous: deskSlots)
        roomOrder = OfficePlan.roomOrder(members, previous: roomOrder)
        return OfficePlan.make(members, slots: deskSlots, order: roomOrder)
    }

    /// Henüz bakılmamış proje klasörlerinin ikonunu arka planda bulur.
    func loadProjectIcons(_ directories: [String]) {
        for directory in directories where !iconLookups.contains(directory) {
            iconLookups.insert(directory)
            Task { [weak self] in
                let icon = await Task.detached(priority: .utility) { () -> LoadedProjectIcon in
                    switch ProjectIconLocator.locate(directory: directory) {
                    case .image(let path):
                        if let image = NSImage(contentsOfFile: path) { return .image(image) }
                        return .symbol(LoadedProjectIcon.symbol(for: .generic))
                    case .kind(let kind):
                        return .symbol(LoadedProjectIcon.symbol(for: kind))
                    }
                }.value
                self?.projectIcons[directory] = icon
            }
        }
    }
}

enum LoadedProjectIcon: @unchecked Sendable {
    case image(NSImage)
    case symbol(String)

    static func symbol(for kind: ProjectKind) -> String {
        switch kind {
        case .unity: "cube.fill"
        case .swift: "swift"
        case .web: "globe"
        case .android: "iphone"
        case .generic: "folder.fill"
        }
    }
}

extension AppModel {
    /// Kullanıcı bu oturumu şu an görüyor mu: odaktaki panel, çalışma ya da odak modu, uygulama önde.
    func isWatched(_ id: String) -> Bool {
        layout.focused == id && mode != .office && NSApp.isActive
    }

    /// Uygulamaya dönünce ya da mod değişince odaktaki oturumun "bitti" işareti kalkar.
    func markFocusedSeen() {
        if let id = layout.focused, isWatched(id) { store.markSeen(id) }
    }

    /// Claude'un oturum başlığını (ai-title) kayıt dosyasının sonundan arka planda okur; en fazla 5 sn'de bir.
    func refreshWorkTitle(_ id: String, transcript path: String) {
        let now = Date()
        if let last = titleReads[id], now.timeIntervalSince(last) < 5 { return }
        titleReads[id] = now
        Task { [weak self] in
            let title = await Task.detached(priority: .utility) { TranscriptTitle.latestTitle(in: URL(fileURLWithPath: path)) }.value
            guard let self, let title, self.store.session(id)?.workTitle != title else { return }
            self.store.setWorkTitle(title, for: id)
            if var record = self.records[id] {
                record.workTitle = title
                self.records[id] = record
                self.saveRecords()
            }
        }
    }

    /// Panel, liste ve ofiste gösterilen "ne üzerinde çalışıyor" metni.
    func workSummary(for id: String) -> String? { store.session(id)?.workSummary }
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
    /// `takeKeyboard: false`: terminal gösterilir ama klavye yerinde kalır (listede ok tuşlarıyla gezinirken).
    func showTerminal(_ id: String, takeKeyboard: Bool = true) {
        defer { store.markSeen(id) }
        // Kaldırılmış bir oturumun eski bildirimine tıklanırsa boş panel açılmasın.
        guard store.session(id) != nil else { return }
        layout.show(id)
        if mode == .office { mode = .work }
        if takeKeyboard { focusTerminalView() } else { releaseTerminalKeyboard() }
    }

    func addTerminal(_ id: String, takeKeyboard: Bool = true) {
        defer { store.markSeen(id) }
        guard store.session(id) != nil else { return }
        layout.add(id)
        if mode == .office { mode = .work }
        if takeKeyboard { focusTerminalView() } else { releaseTerminalKeyboard() }
    }

    /// Yeni yerleşen terminal pencereye girince klavyeyi kapmasın.
    func releaseTerminalKeyboard() {
        for terminal in terminals.values { terminal.wantsKeyboard = false }
    }

    func closePane(_ id: String) {
        layout.close(id)
        focusTerminalView()
    }

    func noteRecentProject(_ path: String) {
        recentProjects = RecentProjects.adding(path, to: recentProjects)
        UserDefaults.standard.set(recentProjects, forKey: "recentProjects")
    }

    /// ⌘T: odaktaki panelin yerine, ⌘D: yanına boş "yeni" panel açar; orada terminal ya da Claude seçilir.
    func openLauncher(beside: Bool, claude: Bool = false) {
        let id = TerminalLayout.launcherPrefix + (claude ? "claude-" : "") + UUID().uuidString.lowercased()
        if beside { layout.add(id) } else { layout.show(id) }
        if mode == .office { mode = .work }
        releaseTerminalKeyboard()
    }

    static func launcherStartsWithClaude(_ id: String) -> Bool {
        id.hasPrefix(TerminalLayout.launcherPrefix + "claude-")
    }

    func finishPermissions() {
        UserDefaults.standard.set(true, forKey: "permissionsShown")
        showPermissions = false
    }

    func zoom(by step: Double) {
        terminalFontSize = min(max(terminalFontSize + step, 8), 36)
    }

    func resetZoom() {
        terminalFontSize = appearance.fontSize
    }

    func cycleFocus(backward: Bool = false) {
        layout.cycle(backward: backward)
        focusTerminalView()
    }

    /// ⌘[ / ⌘]: odaktaki paneldeki oturumu listedeki önceki / sonrakiyle değiştirir; başka panelde açık olanları atlar.
    func showAdjacentSession(_ offset: Int) {
        guard let next = layout.adjacent(in: store.sessions.map(\.id), offset: offset) else { return }
        showTerminal(next)
    }

    func jumpToWaiting() {
        let ids = store.sessions.map(\.id)
        let next = WaitingNavigator.next(after: layout.focused, ids: ids) { id in
            if case .waiting = self.store.session(id)?.state { true } else { false }
        }
        guard let next else { return }
        // Ofis modunda önce kamera masaya gider; tıklayınca terminal açılır.
        if mode == .office {
            layout.show(next)
            officeFocusRequest = next
        } else {
            showTerminal(next)
        }
    }

    /// Odaktaki terminal klavyeyi alır; panel yeni açıldıysa pencereye yerleştiği anda alır.
    func focusTerminalView() {
        for (id, terminal) in terminals { terminal.wantsKeyboard = id == layout.focused }
        guard let id = layout.focused, let terminal = terminals[id] else { return }
        DispatchQueue.main.async { terminal.takeKeyboard() }
    }

    /// Terminal tıklanarak klavyeyi aldığında: görünür panellerdense odak vurgusunu ona taşı.
    func noteKeyboardFocus(_ id: String) {
        store.markSeen(id)
        DebugLog.write("noteKeyboardFocus \(id) visible=\(layout.visible.contains(id)) focused=\(layout.focused ?? "-")")
        guard layout.visible.contains(id), layout.focused != id else { return }
        layout.show(id)
        for (other, terminal) in terminals { terminal.wantsKeyboard = other == id }
    }
}

extension AppModel {
    /// `AGENT_OFFICE_DEMO=1`: sahneyi her durumla görmek için sahte oturumlar (ekran görüntüsü ve geliştirme için).
    func loadDemoSessions() {
        let demo: [(String, String, [AgentEvent])] = [
            ("juice-merge", "/demo/juice-merge", [.sessionStarted(providerSessionID: nil), .promptSubmitted(text: "x"), .toolStarted(name: "Edit", summary: nil)]),
            ("juice-merge-worktree1", "/demo/juice-merge-worktree1", [.sessionStarted(providerSessionID: nil), .promptSubmitted(text: "x"), .needsInput(.question("Hangi renk?"))]),
            ("juice-merge-worktree2", "/demo/juice-merge-worktree2", [.sessionStarted(providerSessionID: nil)]),
            ("room-logic", "/demo/room-logic", [.sessionStarted(providerSessionID: nil), .promptSubmitted(text: "x"), .toolStarted(name: "Bash", summary: nil)]),
            ("api", "/demo/api", [.sessionStarted(providerSessionID: nil)]),
            ("agent-office", "/demo/agent-office", [.sessionEnded]),
        ]
        for (index, item) in demo.enumerated() {
            let id = "demo-\(index)"
            store.register(id: id, title: item.0, cwd: item.1)
            store.apply(item.2, to: id)
        }
        for (index, state) in [AgentState.idle, .working(tool: "npm")].enumerated() {
            let id = "demo-shell-\(index)"
            records[id] = SessionRecord(id: id, title: "api", cwd: "/demo/api", claudeSessionID: nil, createdAt: .now, kind: .shell)
            store.register(id: id, title: "api", cwd: "/demo/api", state: state)
        }
        // "Ne üzerinde çalışıyor" ve "bitti, görülmedi" demo verisi.
        store.setWorkTitle("Birleştirme animasyonunu düzelt", for: "demo-0")
        store.setWorkTitle("Seviye editöründe ızgara hatası", for: "demo-1")
        store.apply([.promptSubmitted(text: "API sayfalamasını ekle"), .turnEnded], to: "demo-4", watched: false)
        // Demo klasörleri gerçek depo değil: worktree'ler elle aynı odaya konur.
        for worktree in ["/demo/juice-merge-worktree1", "/demo/juice-merge-worktree2"] {
            roomIdentities[worktree] = RepoIdentity.Identity(roomKey: "/demo/juice-merge", worktree: (worktree as NSString).lastPathComponent)
            roomKeyLookups.insert(worktree)
        }
        // AGENT_OFFICE_DEMO_REPO + AGENT_OFFICE_DEMO_BASE: ilk demo oturumunun diff'i gerçek bir depodan gelsin.
        let env = ProcessInfo.processInfo.environment
        if let repo = env["AGENT_OFFICE_DEMO_REPO"] {
            var record = SessionRecord(id: "demo-0", title: "juice-merge", cwd: repo, claudeSessionID: nil, createdAt: .now)
            record.baseline = env["AGENT_OFFICE_DEMO_BASE"]
            records["demo-0"] = record
        }
        layout.show("demo-0")
        switch env["AGENT_OFFICE_DEMO_MODE"] {
        case "office": mode = .office
        case "focus": mode = .focus
        default: break
        }
    }
}
