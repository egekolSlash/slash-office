import Testing
@testable import AgentOfficeCore

@Suite struct ResumePlanTests {
    @Test func resumesLatestIDWithTranscript() {
        let plan = ResumePlan.decide(candidates: ["new", "old", "office"], transcriptExists: { $0 != "new" }, freshID: { "fresh" })
        #expect(plan == ResumePlan(claudeSessionID: "old", resume: true))
    }

    @Test func freshIDWhenNoTranscriptAnywhere() {
        // Ofis kimliğiyle --session-id tekrar denenirse "already in use" hatası alınabilir; her zaman yeni kimlik.
        let plan = ResumePlan.decide(candidates: ["a", "b"], transcriptExists: { _ in false }, freshID: { "fresh" })
        #expect(plan == ResumePlan(claudeSessionID: "fresh", resume: false))
    }

    @Test func recordKeepsHistoryNewestFirst() {
        var record = SessionRecord(id: "office", title: "t", cwd: "/", claudeSessionID: nil, createdAt: .now)
        record.noteClaudeSession("office")
        record.noteClaudeSession("x")
        record.noteClaudeSession("x")
        record.noteClaudeSession("y")
        #expect(record.claudeSessionID == "y")
        #expect(record.resumeCandidates == ["y", "x", "office"])
    }
}
