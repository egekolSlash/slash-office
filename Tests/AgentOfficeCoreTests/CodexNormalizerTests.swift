import Foundation
import Testing
@testable import AgentOfficeCore

/// Codex hook payload'ları dokümandaki şemadan (learn.chatgpt.com/docs/hooks): alan adları Claude'unkiyle aynı.
@Suite struct CodexNormalizerTests {
    @Test func sessionStartCarriesTheThreadID() {
        let events = CodexNormalizer.events(from: json(#"{"hook_event_name":"SessionStart","session_id":"019e-abc","source":"startup","cwd":"/p","model":"gpt-5.5"}"#))
        #expect(events == [.sessionStarted(providerSessionID: "019e-abc")])
    }

    @Test func promptStartsTheTurn() {
        let events = CodexNormalizer.events(from: json(#"{"hook_event_name":"UserPromptSubmit","turn_id":"t1","prompt":"fix the bug"}"#))
        #expect(events == [.promptSubmitted(text: "fix the bug")])
    }

    @Test func bashShowsTheCommand() {
        let events = CodexNormalizer.events(from: json(#"{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"c1","tool_input":{"command":"swift test --filter Foo"}}"#))
        #expect(events == [.toolStarted(name: "Bash", summary: "swift test --filter Foo")])
    }

    @Test func applyPatchTouchesItsFiles() {
        let patch = "*** Begin Patch\n*** Add File: hello.txt\n+hi\n*** Update File: Sources/App.swift\n@@\n-a\n+b\n*** Move to: Sources/Main.swift\n*** Delete File: old.txt\n*** End Patch\n"
        let input = JSONValue.object(["command": .string(patch)])
        let pre = CodexNormalizer.events(from: .object(["hook_event_name": .string("PreToolUse"), "tool_name": .string("apply_patch"), "tool_input": input]))
        #expect(pre == [.toolStarted(name: "apply_patch", summary: "hello.txt")])
        let post = CodexNormalizer.events(from: .object(["hook_event_name": .string("PostToolUse"), "tool_name": .string("apply_patch"), "tool_input": input]))
        #expect(post == [.toolFinished(name: "apply_patch", touchedFiles: ["hello.txt", "Sources/App.swift", "Sources/Main.swift", "old.txt"])])
    }

    @Test func updatePlanFillsTheToDoTab() {
        let events = CodexNormalizer.events(from: json(#"""
        {"hook_event_name":"PreToolUse","tool_name":"update_plan","tool_input":{"explanation":"x","plan":[
          {"step":"Read the code","status":"completed"},{"step":"Fix it","status":"in_progress"},{"step":"Test","status":"pending"}]}}
        """#))
        #expect(events == [.toolStarted(name: "update_plan", summary: nil),
                           .todosChanged([TodoItem(title: "Read the code", status: .done),
                                          TodoItem(title: "Fix it", status: .inProgress),
                                          TodoItem(title: "Test", status: .pending)])])
    }

    @Test func requestUserInputAsksAQuestion() {
        let events = CodexNormalizer.events(from: json(#"{"hook_event_name":"PreToolUse","tool_name":"request_user_input","tool_input":{"questions":[{"id":"q1","header":"DB","question":"Which database?","options":[{"label":"Postgres"}]}]}}"#))
        #expect(events == [.toolStarted(name: "request_user_input", summary: nil), .needsInput(.question("Which database?"))])
    }

    @Test func permissionRequestWaitsForTheUser() {
        let described = CodexNormalizer.events(from: json(#"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf build","description":"Remove the build folder"}}"#))
        #expect(described == [.needsInput(.permission("Remove the build folder"))])
        let bare = CodexNormalizer.events(from: json(#"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf build","description":null}}"#))
        #expect(bare == [.needsInput(.permission("rm -rf build"))])
    }

    @Test func turnEndsInterruptsAndSessionEnds() {
        #expect(CodexNormalizer.events(from: json(#"{"hook_event_name":"Stop","turn_id":"t1","stop_hook_active":false,"last_assistant_message":"done"}"#)) == [.turnEnded])
        #expect(CodexNormalizer.events(from: json(#"{"hook_event_name":"Interrupt","turn_id":"t1"}"#)) == [.interrupted])
        #expect(CodexNormalizer.events(from: json(#"{"hook_event_name":"SessionEnd","reason":"other"}"#)) == [.sessionEnded])
        #expect(CodexNormalizer.events(from: json(#"{"hook_event_name":"PreCompact","trigger":"auto"}"#)).isEmpty)
    }

    @MainActor @Test func aTurnGoesWorkingWaitingIdle() {
        let store = AgentStore()
        store.register(id: "s", title: "p", cwd: "/p", state: .idle)
        store.apply(CodexNormalizer.events(from: json(#"{"hook_event_name":"UserPromptSubmit","prompt":"go"}"#)), to: "s")
        store.apply(CodexNormalizer.events(from: json(#"{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}"#)), to: "s")
        #expect(store.session("s")?.state == .working(tool: "Bash"))
        store.apply(CodexNormalizer.events(from: json(#"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}"#)), to: "s")
        #expect(store.session("s")?.state == .waiting(.permission("ls")))
        store.apply(CodexNormalizer.events(from: json(#"{"hook_event_name":"Stop"}"#)), to: "s")
        #expect(store.session("s")?.state == .idle)
    }
}

/// Antigravity CLI payload'ları gerçek bir `agy -p` çalıştırmasından (yollar temizlendi).
@Suite struct AntigravityNormalizerTests {
    @Test func sessionStartCarriesTheConversationID() throws {
        let events = AntigravityNormalizer.events(from: try fixture("antigravity", "SessionStart"))
        #expect(events == [.sessionStarted(providerSessionID: "2459dff3-a328-42fd-93b3-1a64f5b09618")])
    }

    @Test func onlyTheFirstModelCallStartsTheTurn() throws {
        let first = AntigravityNormalizer.events(from: try fixture("antigravity", "PreInvocation-first"))
        guard case .promptSubmitted(let text)? = first.first, first.count == 1 else { Issue.record("\(first)"); return }
        #expect(text.hasPrefix("Make a short todo/plan"))
        #expect(AntigravityNormalizer.events(from: try fixture("antigravity", "PreInvocation-later")).isEmpty)
    }

    @Test func toolsShowCommandAndFiles() throws {
        #expect(AntigravityNormalizer.events(from: try fixture("antigravity", "PreToolUse-run_command"))
            == [.toolStarted(name: "run_command", summary: "ls")])
        #expect(AntigravityNormalizer.events(from: try fixture("antigravity", "PostToolUse-run_command"))
            == [.toolFinished(name: "run_command", touchedFiles: [])])
        #expect(AntigravityNormalizer.events(from: try fixture("antigravity", "PostToolUse-write_file"))
            == [.toolFinished(name: "write_file", touchedFiles: ["/Users/me/proj/hello.txt"])])
        #expect(AntigravityNormalizer.events(from: try fixture("antigravity", "PostToolUse-edit_file"))
            == [.toolFinished(name: "edit_file", touchedFiles: ["/Users/me/proj/hello.txt"])])
    }

    @MainActor @Test func askQuestionWaitsAndTheAnswerResumesWork() {
        let store = AgentStore()
        store.register(id: "s", title: "p", cwd: "/p", state: .idle)
        let call = #""toolCall":{"id":"c1","name":"ask_question","args":{"questions":[{"question":"Which color?","options":["red","blue"]}]}}"#
        store.apply(AntigravityNormalizer.events(from: json(#"{"hookEventName":"PreToolUse",\#(call)}"#)), to: "s")
        #expect(store.session("s")?.state == .waiting(.question("Which color?")))
        store.apply(AntigravityNormalizer.events(from: json(#"{"hookEventName":"PostToolUse","error":"",\#(call)}"#)), to: "s")
        #expect(store.session("s")?.state == .working(tool: nil))
        store.apply(AntigravityNormalizer.events(from: json(#"{"hookEventName":"Stop","terminationReason":"NO_TOOL_CALL"}"#)), to: "s")
        #expect(store.session("s")?.state == .idle)
    }

    @Test func stopEndsOrCancelsTheTurn() throws {
        #expect(AntigravityNormalizer.events(from: try fixture("antigravity", "Stop")) == [.turnEnded])
        #expect(AntigravityNormalizer.events(from: json(#"{"hookEventName":"Stop","terminationReason":"USER_CANCELED"}"#)) == [.interrupted])
    }
}
