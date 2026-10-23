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
        public var todos: [TodoItem] = []
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
        public var backgroundTasks: [BackgroundTask] = []

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
            case .sessionStarted(let providerID?): session.providerSessionID = providerID
            case .promptSubmitted(let text):
                // Arka plan bildirimi (boş metin) kullanıcının isteği değildir: son istek ve şerit değişmez.
                guard !text.isEmpty else { break }
                session.lastPrompt = text
                session.activity.notePrompt(at: date)
            case .filesTouched(let files):
                for file in files where !session.touchedFiles.contains(file) { session.touchedFiles.append(file) }
            case .todosChanged(let todos): session.todos = todos
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
    }

    public func markExited(_ id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].state = .exited
        sessions[index].activity.note(busy: false, at: .now)
    }

    /// Kapanmış bir oturum yeniden başlatılırken durumu sıfırlar.
    public func restart(_ id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].state = .starting
    }

    public func remove(_ id: String) {
        sessions.removeAll { $0.id == id }
    }
}
