import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct TranscriptReaderTests {
    static let user = #"{"type":"user","uuid":"u1","timestamp":"2026-10-15T10:00:00Z","isSidechain":false,"message":{"role":"user","content":"Testleri çalıştır"}}"#
    static let thinking = #"{"type":"assistant","uuid":"a0","isSidechain":false,"message":{"content":[{"type":"thinking","thinking":"..."}]}}"#
    static let tool = #"{"type":"assistant","uuid":"a1","isSidechain":false,"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"swift test"}}]}}"#
    static let result = #"{"type":"user","uuid":"u2","isSidechain":false,"message":{"content":[{"type":"tool_result","content":"ok"}]}}"#
    static let answer = #"{"type":"assistant","uuid":"a2","isSidechain":false,"message":{"content":[{"type":"text","text":"Hepsi geçti."}]}}"#
    static let side = #"{"type":"assistant","uuid":"s1","isSidechain":true,"message":{"content":[{"type":"text","text":"alt ajan"}]}}"#
    static let meta = #"{"type":"user","uuid":"m1","isMeta":true,"isSidechain":false,"message":{"content":"meta"}}"#
    static let command = #"{"type":"user","uuid":"c1","isSidechain":false,"message":{"content":"<command-name>/clear</command-name>"}}"#
    static let title = #"{"type":"ai-title","aiTitle":"Testler"}"#

    func file(_ lines: [String], trailingNewline: Bool = true) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID().uuidString).jsonl")
        try Data((lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")).utf8).write(to: url)
        return url
    }

    @Test func keepsTheConversationOnly() {
        let lines = [Self.user, Self.thinking, Self.tool, Self.result, Self.answer, Self.side, Self.meta, Self.command, Self.title]
        let messages = TranscriptReader.messages(fromLines: lines.map { Substring($0) })
        #expect(messages.map(\.role) == [.user, .tool, .assistant])
        #expect(messages.map(\.text) == ["Testleri çalıştır", "Bash swift test", "Hepsi geçti."])
        #expect(messages[0].id == "u1:0" && messages[0].time == "2026-10-15T10:00:00Z")
    }

    @Test func readsFromTheCursor() throws {
        let url = try file([Self.user, Self.answer])
        let first = try #require(TranscriptReader.read(url: url, from: 0))
        #expect(first.messages.count == 2)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((Self.tool + "\n").utf8))
        try handle.close()
        let next = try #require(TranscriptReader.read(url: url, from: first.cursor))
        #expect(next.messages.map(\.text) == ["Bash swift test"])
    }

    @Test func partialLineIsNotConsumed() throws {
        let url = try file([Self.user, String(Self.answer.prefix(30))], trailingNewline: false)
        let page = try #require(TranscriptReader.read(url: url, from: 0))
        #expect(page.messages.map(\.text) == ["Testleri çalıştır"])
        #expect(page.cursor == UInt64(Self.user.utf8.count + 1))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((String(Self.answer.dropFirst(30)) + "\n").utf8))
        try handle.close()
        let next = try #require(TranscriptReader.read(url: url, from: page.cursor))
        #expect(next.messages.map(\.text) == ["Hepsi geçti."])
    }

    @Test func tailDoesNotDropALineCaughtMidWrite() throws {
        let url = try file([String(Self.answer.prefix(30))], trailingNewline: false)
        let page = try #require(TranscriptReader.tail(url: url))
        #expect(page.messages.isEmpty)
        #expect(page.cursor == 0)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((String(Self.answer.dropFirst(30)) + "\n").utf8))
        try handle.close()
        let next = try #require(TranscriptReader.read(url: url, from: 0))
        #expect(next.messages.map(\.text) == ["Hepsi geçti."])
    }

    @Test func tailKeepsTheLastMessages() throws {
        let url = try file(Array(repeating: Self.answer, count: 10))
        let page = try #require(TranscriptReader.tail(url: url, maxMessages: 3))
        #expect(page.messages.count == 3)
        #expect(page.cursor == UInt64((Self.answer.utf8.count + 1) * 10))
    }

    @Test func missingFileIsNil() {
        #expect(TranscriptReader.read(url: URL(fileURLWithPath: "/nonexistent/x.jsonl"), from: 0) == nil)
    }

    @Test func cursorPastTheEndStaysAtTheEnd() throws {
        let url = try file([Self.user])
        let page = try #require(TranscriptReader.read(url: url, from: 10_000))
        #expect(page.messages.isEmpty)
        #expect(page.cursor == UInt64(Self.user.utf8.count + 1))
    }
}
