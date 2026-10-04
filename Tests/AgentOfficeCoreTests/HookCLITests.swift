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
}
