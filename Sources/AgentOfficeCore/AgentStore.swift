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

    public func apply(_ events: [AgentEvent], to id: String, at date: Date = .now) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var session = sessions[index]
        for event in events {
            session.state = AgentStateMachine.reduce(session.state, event)
            switch event {
            case .sessionStarted(let providerID?): session.providerSessionID = providerID
            case .promptSubmitted(let text): session.lastPrompt = text
            case .todosChanged(let todos): session.todos = todos
            default: break
            }
        }
        session.lastEventAt = date
        sessions[index] = session
    }

    /// Hook'u olmayan oturumlar (shell) için durumu doğrudan ayarlar; değişmediyse yazmaz.
    public func setState(_ state: AgentState, for id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].state != state else { return }
        sessions[index].state = state
    }

    public func markExited(_ id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].state = .exited
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
