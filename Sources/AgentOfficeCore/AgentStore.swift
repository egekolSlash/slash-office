import Foundation
import Observation

@MainActor
@Observable
public final class AgentStore {
    public struct Session: Identifiable, Equatable, Sendable {
        public let id: String
        public var title: String
        public var cwd: String
        public var state: AgentState = .starting
        /// Claude'un adım adım planı (görev araçları ya da TodoWrite).
        public var todos: [TodoItem] = []
        /// Plan modunda önerilen son plan (Markdown).
        public var plan: String?
        public var lastPrompt: String?
        public var providerSessionID: String?
        public var lastEventAt: Date?
        /// Durum sınıfına (çalışıyor, bekliyor, boşta...) ne zaman girdi; kendiliğinden odakta aynı öncelikte en yeni kazanır.
        public var attentionSince: Date?
        /// Ajanın tool'larla dokunduğu dosyalar (git olmayan klasörlerde diff yerine gösterilir).
        public var touchedFiles: [String] = []
        /// Claude'un oturuma verdiği başlık (ai-title).
        public var workTitle: String?
        /// Çalışırken işini bitirdi ve kullanıcı henüz görmedi.
        public var unseenFinish = false
        /// Son bir saatteki çalışma ve istekler (listedeki aktiflik şeridi).
        public var activity = ActivityLog()
        /// Tur bitse de süren arka plan işleri (başlama sırasıyla). Kalıcı değil.
        public var backgroundTasks: [BackgroundJob] = []

        /// Ne üzerinde çalışıyor: başlık, yoksa son isteğin kısaltılmışı.
        public var workSummary: String? {
            if let workTitle { return workTitle }
            guard let prompt = lastPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty else { return nil }
            let line = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
            return line.count > 80 ? String(line.prefix(79)) + "…" : line
        }
    }

    public private(set) var sessions: [Session] = []

    public init() {}

    public var waitingCount: Int {
        sessions.filter { if case .waiting = $0.state { true } else { false } }.count
    }

    public func session(_ id: String) -> Session? {
        sessions.first { $0.id == id }
    }

    public func register(id: String, title: String, cwd: String, state: AgentState = .starting) {
        guard session(id) == nil else { return }
        sessions.append(Session(id: id, title: title, cwd: cwd, state: state))
    }

    /// `watched`: kullanıcı bu oturumu şu an görüyor (odaktaki panel ve uygulama önde). Görmüyorken
    /// çalışma → boşta geçişi "bitti, görülmedi" olarak işaretlenir; yeni iş başlayınca işaret kalkar.
    public func apply(_ events: [AgentEvent], to id: String, at date: Date = .now, watched: Bool = true) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var session = sessions[index]
        for event in events {
            Self.noteBackground(&session, event)
            let previous = session.state
            session.state = AgentStateMachine.reduce(session.state, event)
            Self.noteFinish(&session, from: previous, watched: watched)
            Self.noteAttention(&session, from: previous, at: date)
            switch event {
            case .sessionStarted(let providerID?):
                // /clear: Claude yeni oturum kimliğiyle baştan başlar, görev listesi de yenidir.
                if let previous = session.providerSessionID, previous != providerID {
                    session.todos = []
                    session.plan = nil
                }
                session.providerSessionID = providerID
            case .promptSubmitted(let text):
                // Arka plan bildirimi (boş metin) kullanıcının isteği değildir: son istek ve şerit değişmez.
                guard !text.isEmpty else { break }
                session.lastPrompt = text
                session.activity.notePrompt(at: date)
            case .filesTouched(let files):
                for file in files where !session.touchedFiles.contains(file) { session.touchedFiles.append(file) }
            case .todosChanged(let todos): session.todos = todos
            case .taskCreated, .taskUpdated, .taskDeleted: Self.noteTask(&session.todos, event)
            case .planProposed(let plan): session.plan = plan
            case .toolFinished(_, let files):
                for file in files where !session.touchedFiles.contains(file) { session.touchedFiles.append(file) }
            default: break
            }
        }
        session.lastEventAt = date
        sessions[index] = session
    }

    /// Hook'u olmayan oturumlar (shell) için durumu doğrudan ayarlar; değişmediyse yazmaz.
    public func setState(_ state: AgentState, for id: String, watched: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].state != state else { return }
        let previous = sessions[index].state
        sessions[index].state = state
        Self.noteFinish(&sessions[index], from: previous, watched: watched)
        Self.noteAttention(&sessions[index], from: previous, at: .now)
    }

    public func markSeen(_ id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].unseenFinish else { return }
        sessions[index].unseenFinish = false
    }

    public func setWorkTitle(_ title: String?, for id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].workTitle != title else { return }
        sessions[index].workTitle = title
    }

    static func noteAttention(_ session: inout Session, from previous: AgentState, at date: Date) {
        guard session.state.stateClass != previous.stateClass else { return }
        session.attentionSince = date
        let busy = if case .working = session.state { true } else { false }
        session.activity.note(busy: busy, at: date)
    }

    static func noteFinish(_ session: inout Session, from previous: AgentState, watched: Bool) {
        if case .working = session.state { session.unseenFinish = false; return }
        if case .working = previous, session.state == .idle, session.backgroundTasks.isEmpty, !watched { session.unseenFinish = true }
    }

    /// Görev araçlarından gelen tek adımlık değişiklikler. Bütün adımları bitmiş bir plana yeni adım gelirse
    /// yeni bir plan başlamıştır: eskisi silinir.
    static func noteTask(_ todos: inout [TodoItem], _ event: AgentEvent) {
        switch event {
        case .taskCreated(let id, let title):
            if !todos.isEmpty, todos.allSatisfy({ $0.status == .done }) { todos = [] }
            if let i = todos.firstIndex(where: { $0.id == id }) { todos[i].title = title }
            else { todos.append(TodoItem(id: id, title: title, status: .pending)) }
        case .taskUpdated(let id, let status, let title):
            guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
            if let status { todos[i].status = status }
            if let title { todos[i].title = title }
        case .taskDeleted(let id):
            todos.removeAll { $0.id == id }
        default:
            break
        }
    }

    static func noteBackground(_ session: inout Session, _ event: AgentEvent) {
        switch event {
        case .backgroundStarted(let task):
            if let i = session.backgroundTasks.firstIndex(where: { $0.id == task.id }) { session.backgroundTasks[i] = task }
            else { session.backgroundTasks.append(task) }
        case .backgroundFinished(let id):
            session.backgroundTasks.removeAll { $0.id == id }
        case .backgroundSnapshot(let tasks):
            session.backgroundTasks = tasks
        case .sessionEnded:
            session.backgroundTasks = []
        default:
            break
        }
    }

    public func setState(_ state: AgentState, for id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].state != state else { return }
        let previous = sessions[index].state
        sessions[index].state = state
        Self.noteAttention(&sessions[index], from: previous, at: .now)
    }

    /// Shell oturumu başka klasöre geçti (`cd`): proje, başlık ve o projeye ait izler güncellenir.
    public func relocate(_ id: String, cwd: String, title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].cwd != cwd else { return }
        sessions[index].cwd = cwd
        sessions[index].title = title
        sessions[index].touchedFiles = []
        sessions[index].todos = []
        sessions[index].plan = nil
    }

    public func markExited(_ id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].state = .exited
        sessions[index].activity.note(busy: false, at: .now)
    }

    /// Diskten okunan görev listesi. Hook'lardan gelen liste daha yeni olabilir: sadece listede olmayan bir adım
    /// varsa (uygulama kapalıyken eklenmiş) ya da liste boşsa yerine geçer.
    public func restoreTodos(_ todos: [TodoItem], for id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), !todos.isEmpty else { return }
        let known = Set(sessions[index].todos.compactMap(\.id))
        let usesTasks = sessions[index].todos.allSatisfy { $0.id != nil }
        guard usesTasks, sessions[index].todos.isEmpty || todos.contains(where: { !known.contains($0.id ?? "") }) else { return }
        sessions[index].todos = todos
    }

    /// Kapanmış bir oturum yeniden başlatılırken durumu sıfırlar.
    public func restart(_ id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].state = .starting
    }

    /// Elle verilen sıra: listede olmayan kimlikler yok sayılır, sırada olmayan oturumlar eski sıralarıyla sona eklenir.
    public func reorder(_ ids: [String]) {
        let rank = Dictionary(ids.enumerated().map { ($1, $0) }) { first, _ in first }
        let reordered = sessions.enumerated()
            .sorted { (rank[$0.element.id] ?? ids.count + $0.offset, $0.offset) < (rank[$1.element.id] ?? ids.count + $1.offset, $1.offset) }
            .map(\.element)
        guard reordered.map(\.id) != sessions.map(\.id) else { return }
        sessions = reordered
    }

    public func remove(_ id: String) {
        sessions.removeAll { $0.id == id }
    }
}
