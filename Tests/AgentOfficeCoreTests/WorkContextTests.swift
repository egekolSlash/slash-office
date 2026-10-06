import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct WorkContextTests {
    func transcript(_ lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID()).jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func latestAiTitleWins() throws {
        let url = try transcript([
            #"{"type":"user","message":"x"}"#,
            #"{"type":"ai-title","aiTitle":"İlk başlık","sessionId":"s"}"#,
            #"{"type":"assistant","message":"y"}"#,
            #"{"type":"ai-title","aiTitle":"Birleştirme animasyonunu düzelt","sessionId":"s"}"#,
            #"{"type":"user","message":"z"}"#,
        ])
        #expect(TranscriptTitle.latestTitle(in: url) == "Birleştirme animasyonunu düzelt")
    }

    @Test func skipsBrokenLinesAndMissingFile() throws {
        let url = try transcript([#"{"type":"ai-title","aiTitle":"Başlık"}"#, #"{"type":"ai-title","aiTi"#])
        #expect(TranscriptTitle.latestTitle(in: url) == "Başlık")
        #expect(TranscriptTitle.latestTitle(in: URL(fileURLWithPath: "/nope/x.jsonl")) == nil)
        #expect(TranscriptTitle.latestTitle(in: try transcript([#"{"type":"user"}"#])) == nil)
    }

    @Test func readsOnlyTheTailOfLargeFiles() throws {
        let filler = String(repeating: "a", count: 2000)
        var lines = [#"{"type":"ai-title","aiTitle":"Eski"}"#]
        lines += (0..<200).map { _ in #"{"type":"assistant","message":"\#(filler)"}"# }
        lines.append(#"{"type":"ai-title","aiTitle":"Yeni"}"#)
        let url = try transcript(lines)
        #expect(TranscriptTitle.latestTitle(in: url, tailBytes: 8192) == "Yeni")
        // Son kısımda başlık yoksa nil (dosyanın tamamı okunmaz).
        let url2 = try transcript([#"{"type":"ai-title","aiTitle":"Eski"}"#] + (0..<200).map { _ in #"{"type":"assistant","message":"\#(filler)"}"# })
        #expect(TranscriptTitle.latestTitle(in: url2, tailBytes: 8192) == nil)
    }

    @Test func transcriptPathFromPayload() {
        let payload = json(#"{"hook_event_name":"Stop","transcript_path":"/Users/me/.claude/projects/p/s.jsonl"}"#)
        #expect(ClaudeNormalizer.transcriptPath(from: payload) == "/Users/me/.claude/projects/p/s.jsonl")
        #expect(ClaudeNormalizer.transcriptPath(from: json(#"{"hook_event_name":"Stop"}"#)) == nil)
    }

    @Test @MainActor func finishingWhileUnwatchedIsMarkedUntilSeen() {
        let store = AgentStore()
        store.register(id: "s", title: "juice-merge", cwd: "/h", state: .idle)
        store.apply([.promptSubmitted(text: "x")], to: "s", watched: false)
        #expect(store.session("s")?.unseenFinish == false)
        store.apply([.turnEnded], to: "s", watched: false)
        #expect(store.session("s")?.unseenFinish == true)
        store.markSeen("s")
        #expect(store.session("s")?.unseenFinish == false)
        // İzlenirken biten işaretlenmez.
        store.apply([.promptSubmitted(text: "y"), .turnEnded], to: "s", watched: true)
        #expect(store.session("s")?.unseenFinish == false)
        // Yeni tur başlayınca eski işaret kalkar.
        store.apply([.promptSubmitted(text: "z"), .turnEnded], to: "s", watched: false)
        store.apply([.promptSubmitted(text: "w")], to: "s", watched: false)
        #expect(store.session("s")?.unseenFinish == false)
    }

    @Test @MainActor func shellCommandFinishingIsMarked() {
        let store = AgentStore()
        store.register(id: "t", title: "api", cwd: "/a", state: .idle)
        store.setState(.working(tool: "npm"), for: "t", watched: false)
        store.setState(.idle, for: "t", watched: false)
        #expect(store.session("t")?.unseenFinish == true)
    }

    @Test @MainActor func workTitleAndSummary() {
        let store = AgentStore()
        store.register(id: "s", title: "juice-merge", cwd: "/h")
        store.apply([.promptSubmitted(text: String(repeating: "uzun istek ", count: 20))], to: "s")
        #expect(store.session("s")?.workSummary?.count ?? 0 <= 81)
        store.setWorkTitle("Birleştirme animasyonu", for: "s")
        #expect(store.session("s")?.workSummary == "Birleştirme animasyonu")
    }
}
