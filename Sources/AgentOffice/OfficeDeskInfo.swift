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
    /// Ne üzerinde çalışıyor (ai-title ya da son istek).
    var summary: String? = nil
    /// Çalışırken bitti, kullanıcı henüz görmedi.
    var unseenFinish = false
    /// Köylüye verilen ad (kartta başlığın önünde).
    var name: String? = nil
}
