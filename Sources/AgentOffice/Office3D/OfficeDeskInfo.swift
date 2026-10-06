import AgentOfficeCore

/// Bir masanın sahnede çizilmesi için gereken her şey; değişmediyse masa yeniden çizilmez.
struct OfficeDeskInfo: Equatable {
    var id: String
    var title: String
    var state: AgentState
    var kind: SessionKind
    var roomKey: String
    var worktree: String?
    var focused: Bool
}
