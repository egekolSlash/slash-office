/// Durmuş bir Claude oturumunun nasıl yeniden açılacağı.
public struct ResumePlan: Equatable, Sendable {
    public var claudeSessionID: String
    public var resume: Bool

    public init(claudeSessionID: String, resume: Bool) {
        self.claudeSessionID = claudeSessionID
        self.resume = resume
    }

    /// Transcript'i olan en yeni kimlikle `--resume`. Hiçbirinde yoksa yeni bir kimlikle sıfırdan başlar;
    /// eski bir kimliği `--session-id` ile tekrar kullanmak Claude'da "already in use" hatasına yol açabilir.
    public static func decide(candidates: [String], transcriptExists: (String) -> Bool, freshID: () -> String) -> ResumePlan {
        if let id = candidates.first(where: transcriptExists) {
            return ResumePlan(claudeSessionID: id, resume: true)
        }
        return ResumePlan(claudeSessionID: freshID(), resume: false)
    }
}

extension SessionRecord {
    /// Claude'un bildirdiği oturum kimliğini kaydeder (`/clear` sonrası değişir); eskileri geçmişte tutulur.
    public mutating func noteClaudeSession(_ id: String) {
        guard claudeSessionID != id else { return }
        if let current = claudeSessionID { claudeSessionHistory.insert(current, at: 0) }
        claudeSessionHistory.removeAll { $0 == id }
        claudeSessionID = id
    }

    /// En yeniden eskiye, tekrarsız; en sonda ofisin kendi kimliği.
    public var resumeCandidates: [String] {
        var seen = Set<String>()
        return ([claudeSessionID].compactMap { $0 } + claudeSessionHistory + [id]).filter { seen.insert($0).inserted }
    }
}
