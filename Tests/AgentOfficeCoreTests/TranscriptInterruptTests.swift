import Foundation
import Testing
@testable import AgentOfficeCore

struct TranscriptInterruptTests {
    // Gerçek bir kayıttan (Claude Code 2.1): soru Esc ile kesildi.
    static let question = #"{"type":"assistant","isSidechain":false,"message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"AskUserQuestion","input":{}}]}}"#
    static let rejected = #"{"type":"user","isSidechain":false,"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"The user doesn't want to proceed with this tool use."}]}}"#
    static let interrupt = #"{"type":"user","isSidechain":false,"message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#
    static let meta = [#"{"type":"system","subtype":"turn_duration"}"#, #"{"type":"ai-title","aiTitle":"x"}"#, #"{"type":"mode"}"#]

    @Test func interruptedQuestionIsDetected() {
        #expect(TranscriptInterrupt.endsWithInterrupt(lines: [Self.question, Self.rejected, Self.interrupt] + Self.meta))
    }

    @Test func plainInterruptTextIsDetected() {
        let line = #"{"type":"user","message":{"role":"user","content":"[Request interrupted by user]"}}"#
        #expect(TranscriptInterrupt.endsWithInterrupt(lines: [Self.question, line]))
    }

    @Test func openQuestionOrNewPromptIsNotInterrupted() {
        #expect(!TranscriptInterrupt.endsWithInterrupt(lines: [Self.question] + Self.meta))
        let prompt = #"{"type":"user","message":{"role":"user","content":"devam et"}}"#
        #expect(!TranscriptInterrupt.endsWithInterrupt(lines: [Self.question, Self.rejected, Self.interrupt, prompt]))
        #expect(!TranscriptInterrupt.endsWithInterrupt(lines: [Self.interrupt, Self.question]))
        #expect(!TranscriptInterrupt.endsWithInterrupt(lines: []))
    }

    @Test func sidechainEntriesAreIgnored() {
        let side = #"{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[]}}"#
        #expect(TranscriptInterrupt.endsWithInterrupt(lines: [Self.interrupt, side]))
    }

    @Test func readsTheFileTail() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("interrupt-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let filler = String(repeating: "x", count: 40_000)
        let lines = [#"{"type":"user","message":{"content":"\#(filler)"}}"#, Self.question, Self.rejected, Self.interrupt]
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        #expect(TranscriptInterrupt.endsWithInterrupt(in: url))
    }

    @Test func interruptEndsQuestionAndWork() {
        #expect(AgentStateMachine.reduce(.waiting(.question("q")), .interrupted) == .idle)
        #expect(AgentStateMachine.reduce(.waiting(.permission("p")), .interrupted) == .idle)
        #expect(AgentStateMachine.reduce(.working(tool: "Bash"), .interrupted) == .idle)
        #expect(AgentStateMachine.reduce(.idle, .interrupted) == .idle)
        #expect(AgentStateMachine.reduce(.exited, .interrupted) == .exited)
    }

    @MainActor @Test func interruptedQuestionIsNotAFinish() {
        let store = AgentStore()
        store.register(id: "a", title: "a", cwd: "/", state: .waiting(.question("q")))
        store.apply([.interrupted], to: "a", watched: false)
        #expect(store.session("a")?.state == .idle)
        #expect(store.session("a")?.unseenFinish == false)
    }
}
