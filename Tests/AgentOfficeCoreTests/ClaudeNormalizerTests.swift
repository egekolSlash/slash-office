import Testing
@testable import AgentOfficeCore

@Suite struct ClaudeNormalizerTests {
    @Test func sessionStartCarriesSessionID() {
        let events = ClaudeNormalizer.events(from: json(#"{"hook_event_name":"SessionStart","session_id":"abc","source":"startup"}"#))
        #expect(events == [.sessionStarted(providerSessionID: "abc")])
    }

    @Test func promptSubmitted() {
        let events = ClaudeNormalizer.events(from: json(#"{"hook_event_name":"UserPromptSubmit","prompt":"fix the \"bug\"\nnow 🚀"}"#))
        #expect(events == [.promptSubmitted(text: "fix the \"bug\"\nnow 🚀")])
    }

    @Test func preToolUseSummaries() {
        let edit = ClaudeNormalizer.events(from: json(#"{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"/a/b/Main.swift"}}"#))
        #expect(edit == [.toolStarted(name: "Edit", summary: "Main.swift")])
        let longCommand = String(repeating: "x", count: 80)
        let bash = ClaudeNormalizer.events(from: json(#"{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"\#(longCommand)"}}"#))
        #expect(bash == [.toolStarted(name: "Bash", summary: String(repeating: "x", count: 40))])
        let other = ClaudeNormalizer.events(from: json(#"{"hook_event_name":"PreToolUse","tool_name":"WebSearch","tool_input":{}}"#))
        #expect(other == [.toolStarted(name: "WebSearch", summary: nil)])
    }

    @Test func askUserQuestionNeedsInput() {
        let events = ClaudeNormalizer.events(from: json(#"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Hangi renk?"}]}}"#))
        #expect(events == [.toolStarted(name: "AskUserQuestion", summary: nil), .needsInput(.question("Hangi renk?"))])
    }

    @Test func todoWriteProducesTodos() {
        let events = ClaudeNormalizer.events(from: json(#"{"hook_event_name":"PreToolUse","tool_name":"TodoWrite","tool_input":{"todos":[{"content":"A","status":"completed"},{"content":"B","status":"in_progress"},{"content":"C","status":"pending"}]}}"#))
        #expect(events.last == .todosChanged([
            TodoItem(title: "A", status: .done),
            TodoItem(title: "B", status: .inProgress),
            TodoItem(title: "C", status: .pending),
        ]))
    }

    @Test func postToolUseTouchedFiles() {
        let events = ClaudeNormalizer.events(from: json(#"{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"/x/y.txt"},"tool_response":{}}"#))
        #expect(events == [.toolFinished(name: "Write", touchedFiles: ["/x/y.txt"])])
    }

    @Test func permissionNotificationNeedsInput() {
        let typed = ClaudeNormalizer.events(from: json(#"{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash"}"#))
        #expect(typed == [.needsInput(.permission("Claude needs your permission to use Bash"))])
        let untyped = ClaudeNormalizer.events(from: json(#"{"hook_event_name":"Notification","message":"Claude needs your permission to use Bash"}"#))
        #expect(untyped == typed)
    }

    @Test func idleNotificationIsIgnored() {
        let events = ClaudeNormalizer.events(from: json(#"{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"Claude is waiting for your input"}"#))
        #expect(events.isEmpty)
    }

    @Test func stopEndAndUnknown() {
        #expect(ClaudeNormalizer.events(from: json(#"{"hook_event_name":"Stop"}"#)) == [.turnEnded])
        #expect(ClaudeNormalizer.events(from: json(#"{"hook_event_name":"SessionEnd","reason":"exit"}"#)) == [.sessionEnded])
        #expect(ClaudeNormalizer.events(from: json(#"{"hook_event_name":"PreCompact"}"#)).isEmpty)
        #expect(ClaudeNormalizer.events(from: json(#"[1,2]"#)).isEmpty)
    }

    @Test(arguments: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd"])
    func capturedFixtureProducesEvents(name: String) throws {
        #expect(!ClaudeNormalizer.events(from: try fixture("claude", name)).isEmpty)
    }

    @Test func capturedPermissionFixture() throws {
        let events = ClaudeNormalizer.events(from: try fixture("claude", "Notification-permission"))
        guard case .needsInput(.permission) = events.first else {
            Issue.record("expected permission needsInput, got \(events)")
            return
        }
    }

    @Test func capturedAskUserQuestionFixture() throws {
        let events = ClaudeNormalizer.events(from: try fixture("claude", "PreToolUse-AskUserQuestion"))
        guard case .needsInput(.question) = events.last else {
            Issue.record("expected question needsInput, got \(events)")
            return
        }
    }
}
