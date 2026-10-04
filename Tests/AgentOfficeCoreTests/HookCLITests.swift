import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct HookCLITests {
    @Test func envelopeIsSingleLineAndRoundTrips() throws {
        let raw = Data(#"{"hook_event_name":"UserPromptSubmit","prompt":"say \"hi\"\nline2 🚀 'quote'"}"#.utf8)
        let line = try #require(HookEnvelope.encodeLine(session: "s1", provider: "claude", rawPayload: raw))
        #expect(!line.contains(0x0A))
        let decoded = try JSONDecoder().decode(HookEnvelope.self, from: line)
        #expect(decoded.session == "s1")
        #expect(decoded.provider == "claude")
        #expect(decoded.payload["prompt"]?.string == "say \"hi\"\nline2 🚀 'quote'")
    }

    @Test func invalidPayloadIsDropped() {
        #expect(HookEnvelope.encodeLine(session: "s", provider: "claude", rawPayload: Data("not json".utf8)) == nil)
    }

    @Test func tooLongSocketPathIsRejected() {
        #expect(UnixSocket.address(String(repeating: "a", count: 200)) == nil)
        #expect(UnixSocket.address("/tmp/x.sock") != nil)
    }

    @Test func cliExitsZeroQuicklyWithoutListener() {
        let start = Date()
        let code = HookCLI.run(
            arguments: ["agent-office-hook", "claude"],
            environment: ["AGENT_OFFICE_SESSION": "s", "AGENT_OFFICE_SOCKET": "/tmp/ao-missing-\(UUID().uuidString.prefix(8)).sock"],
            stdin: Data(#"{"hook_event_name":"Stop"}"#.utf8)
        )
        #expect(code == 0)
        #expect(Date().timeIntervalSince(start) < 0.3)
    }

    @Test func cliExitsZeroWithoutEnvironment() {
        #expect(HookCLI.run(arguments: ["agent-office-hook"], environment: [:], stdin: Data()) == 0)
    }

    @Test func envelopeDropsToolResponse() throws {
        let raw = Data(#"{"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"/a"},"tool_response":{"content":"huge"}}"#.utf8)
        let line = try #require(HookEnvelope.encodeLine(session: "s", provider: "claude", rawPayload: raw))
        let decoded = try JSONDecoder().decode(HookEnvelope.self, from: line)
        #expect(decoded.payload["tool_response"] == nil)
        #expect(decoded.payload["tool_input"]?["file_path"]?.string == "/a")
    }

    @Test func largeNestedPayloadEncodesQuickly() throws {
        let items = (0..<60_000).map { #"{"line":\#($0),"text":"some output text here"}"# }.joined(separator: ",")
        let raw = Data(#"{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"x"},"tool_response":[\#(items)]}"#.utf8)
        let start = Date()
        let line = try #require(HookEnvelope.encodeLine(session: "s", provider: "claude", rawPayload: raw))
        #expect(Date().timeIntervalSince(start) < 0.3)
        #expect(line.count < 1_000)
    }
}
