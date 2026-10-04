public enum AgentState: Equatable, Sendable {
    case starting
    case idle
    case working(tool: String?)
    case waiting(InputReason)
    case exited
}

public enum AgentStateMachine {
    public static func reduce(_ state: AgentState, _ event: AgentEvent) -> AgentState {
        if state == .exited { return .exited }
        switch event {
        case .sessionStarted:
            // SessionStart compaction/clear sırasında da gelir; sadece ilk açılışta durumu değiştirir.
            return state == .starting ? .idle : state
        case .promptSubmitted:
            return .working(tool: nil)
        case .toolStarted(let name, _):
            return .working(tool: name)
        case .toolFinished:
            return .working(tool: nil)
        case .needsInput(let reason):
            // Claude, AskUserQuestion'dan hemen sonra genel bir izin bildirimi de gönderir; soruyu ezmesin.
            if case .waiting(.question) = state, case .permission = reason { return state }
            return .waiting(reason)
        case .turnEnded:
            return .idle
        case .todosChanged:
            return state
        case .sessionEnded:
            return .exited
        case .inputIdle:
            // Esc ile kesilen turda Stop gelmez. Açık bir soru hâlâ cevap bekliyor olabilir, onu koru.
            switch state {
            case .working, .waiting(.permission): return .idle
            default: return state
            }
        }
    }
}
