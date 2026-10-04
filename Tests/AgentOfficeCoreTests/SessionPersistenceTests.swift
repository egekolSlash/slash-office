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
}
