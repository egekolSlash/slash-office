public enum InputReason: Equatable, Sendable {
    case permission(String)
    case question(String)
}

public struct TodoItem: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case pending, inProgress, done }
    /// Claude'un görev kimliği (TaskCreate); TodoWrite listesinde yok.
    public var id: String?
    public var title: String
    public var status: Status

    public init(id: String? = nil, title: String, status: Status) {
        self.id = id
        self.title = title
        self.status = status
    }
}

/// Turdan bağımsız süren iş: `run_in_background` Bash komutu ya da arka plan subagent'ı.
public struct BackgroundJob: Equatable, Sendable, Identifiable {
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
    /// Claude planına adım ekledi (TaskCreated hook'u).
    case taskCreated(id: String, title: String)
    /// Adımın durumu ya da başlığı değişti (TaskUpdate); nil alan değişmedi.
    case taskUpdated(id: String, status: TodoItem.Status?, title: String?)
    /// Adım plandan çıkarıldı (TaskUpdate, status "deleted").
    case taskDeleted(id: String)
    /// Plan modunda önerilen plan (ExitPlanMode, Markdown).
    case planProposed(String)
    case sessionEnded
    case inputIdle
    /// Kullanıcı turu Esc ile kesti (kayıt dosyasında görüldü; Claude bunun için hook göndermez).
    case interrupted
    /// Arka plan işi başladı (PostToolUse'tan).
    case backgroundStarted(BackgroundJob)
    /// Arka plan işi bitti (Claude'a gelen `<task-notification>`).
    case backgroundFinished(id: String)
    /// Tur sonunda çalışan arka plan işlerinin tam listesi (Stop); listenin yerine geçer.
    case backgroundSnapshot([BackgroundJob])
    /// Subagent'ın dokunduğu dosyalar; ana oturumun durumunu değiştirmez.
    case filesTouched([String])
}
