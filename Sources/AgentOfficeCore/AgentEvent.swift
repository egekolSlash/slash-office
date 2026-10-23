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

/// Turdan bağımsız süren iş: `run_in_background` Bash komutu ya da arka plan subagent'ı.
public struct BackgroundTask: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case shell, subagent }
    public var id: String
    public var kind: Kind
    public var label: String

    public init(id: String, kind: Kind, label: String) {
        self.id = id
        self.kind = kind
        self.label = label
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
    /// Kullanıcı turu Esc ile kesti (kayıt dosyasında görüldü; Claude bunun için hook göndermez).
    case interrupted
    /// Arka plan işi başladı (PostToolUse'tan).
    case backgroundStarted(BackgroundTask)
    /// Arka plan işi bitti (Claude'a gelen `<task-notification>`).
    case backgroundFinished(id: String)
    /// Tur sonunda çalışan arka plan işlerinin tam listesi (Stop); listenin yerine geçer.
    case backgroundSnapshot([BackgroundTask])
    /// Subagent'ın dokunduğu dosyalar; ana oturumun durumunu değiştirmez.
    case filesTouched([String])
}
