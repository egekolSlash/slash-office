public enum InputReason: Equatable, Sendable {
    case permission(String)
    case question(String)
}

public struct TodoItem: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case pending, inProgress, done }
    public var title: String
    public var status: Status

    public init(title: String, status: Status) {
        self.title = title
        self.status = status
    }
}

public enum AgentEvent: Equatable, Sendable {
    case sessionStarted(providerSessionID: String?)
    case promptSubmitted(text: String)
    case toolStarted(name: String, summary: String?)
    case toolFinished(name: String, touchedFiles: [String])
    case needsInput(InputReason)
    case turnEnded
    case todosChanged([TodoItem])
    case sessionEnded
    case inputIdle
}
