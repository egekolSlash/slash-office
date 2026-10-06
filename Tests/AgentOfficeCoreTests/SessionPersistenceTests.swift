import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct SessionPersistenceTests {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ao-\(UUID().uuidString)/sessions.json")
    }

    @Test func roundTripsRecords() throws {
        let url = tempURL()
        let records = [
            SessionRecord(id: "a", title: "proj", cwd: "/p", claudeSessionID: "c1", createdAt: Date(timeIntervalSince1970: 10)),
            SessionRecord(id: "b", title: "other", cwd: "/o", claudeSessionID: nil, createdAt: Date(timeIntervalSince1970: 20)),
        ]
        try SessionStore.save(records, to: url)
        #expect(SessionStore.load(from: url) == records)
    }

    @Test func missingFileLoadsEmpty() {
        #expect(SessionStore.load(from: tempURL()).isEmpty)
    }

    @Test func corruptFileLoadsEmptyAndIsKeptAside() throws {
        let url = tempURL()
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        #expect(SessionStore.load(from: url).isEmpty)
        // Bir sonraki kayıt bozuk dosyanın üstüne yazmasın: kenara alınmış olmalı.
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let aside = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("corrupt") }
        #expect(aside.count == 1)
        #expect(try String(contentsOf: dir.appendingPathComponent(aside[0]), encoding: .utf8) == "{not json")
    }

    @Test func transcriptLookupFindsSessionInAnyProject() throws {
        let projects = FileManager.default.temporaryDirectory.appendingPathComponent("ao-projects-\(UUID().uuidString)")
        let dir = projects.appendingPathComponent("-Users-me-git-test")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data().write(to: dir.appendingPathComponent("abc.jsonl"))
        #expect(ClaudeTranscript.exists(sessionID: "abc", projectsDirectory: projects))
        #expect(!ClaudeTranscript.exists(sessionID: "nope", projectsDirectory: projects))
        #expect(!ClaudeTranscript.exists(sessionID: "abc", projectsDirectory: projects.appendingPathComponent("missing")))
    }

    @Test func recordsWithoutKindLoadAsClaude() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"[{"id":"a","title":"t","cwd":"/p","createdAt":"2026-10-05T10:00:00Z"}]"#.utf8).write(to: url)
        #expect(SessionStore.load(from: url).first?.kind == .claude)
    }

    @Test func shellKindRoundTrips() throws {
        let url = tempURL()
        let record = SessionRecord(id: "s", title: "proj", cwd: "/p", claudeSessionID: nil,
                                   createdAt: Date(timeIntervalSince1970: 0), kind: .shell)
        try SessionStore.save([record], to: url)
        #expect(SessionStore.load(from: url).first?.kind == .shell)
    }

    @Test func baselineRoundTripsAndOldRecordsHaveNone() throws {
        let url = tempURL()
        var record = SessionRecord(id: "s", title: "p", cwd: "/p", claudeSessionID: nil, createdAt: Date(timeIntervalSince1970: 0))
        record.baseline = "abc123"
        try SessionStore.save([record], to: url)
        #expect(SessionStore.load(from: url).first?.baseline == "abc123")
        let old = tempURL()
        try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"[{"id":"a","title":"t","cwd":"/p","createdAt":"2026-10-05T10:00:00Z"}]"#.utf8).write(to: old)
        #expect(SessionStore.load(from: old).first?.baseline == nil)
    }

    @Test func turnTreeRoundTripsAndIsOptional() throws {
        let url = tempURL()
        var record = SessionRecord(id: "s", title: "p", cwd: "/p", claudeSessionID: nil, createdAt: Date(timeIntervalSince1970: 0))
        record.turnTree = "deadbeef"
        try SessionStore.save([record], to: url)
        #expect(SessionStore.load(from: url).first?.turnTree == "deadbeef")
        let old = tempURL()
        try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"[{"id":"a","title":"t","cwd":"/p","createdAt":"2026-10-05T10:00:00Z"}]"#.utf8).write(to: old)
        #expect(SessionStore.load(from: old).first?.turnTree == nil)
    }

    @Test func workTitleRoundTripsAndOldFilesStillLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("s-\(UUID()).json")
        var record = SessionRecord(id: "a", title: "juice-merge", cwd: "/h", claudeSessionID: "a", createdAt: Date(timeIntervalSince1970: 0))
        record.workTitle = "Birleştirme animasyonu"
        try SessionStore.save([record], to: url)
        #expect(SessionStore.load(from: url).first?.workTitle == "Birleştirme animasyonu")
        try #"[{"id":"b","title":"t","cwd":"/c","createdAt":"1970-01-01T00:00:00Z"}]"#.write(to: url, atomically: true, encoding: .utf8)
        #expect(SessionStore.load(from: url).first?.workTitle == nil)
    }
}
