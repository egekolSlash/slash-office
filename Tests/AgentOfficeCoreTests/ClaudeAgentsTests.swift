import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct ClaudeAgentsTests {
    let sample = Data("""
    [
      {"id": "761fddb3", "cwd": "/a", "kind": "background", "sessionId": "761fddb3-aaaa", "state": "blocked"},
      {"pid": 72977, "id": "5ffc161a", "cwd": "/g", "kind": "background", "sessionId": "5ffc161a-bbbb",
       "name": "APK", "status": "busy", "state": "working"},
      {"pid": 74016, "cwd": "/s", "kind": "interactive", "sessionId": "97b8470c-cccc", "status": "idle"},
      {"kind": "future-thing"}
    ]
    """.utf8)

    @Test func parsesEntriesAndSkipsUnknownOnes() {
        let agents = ClaudeAgents.parse(sample)
        #expect(agents.map(\.sessionId) == ["761fddb3-aaaa", "5ffc161a-bbbb", "97b8470c-cccc"])
        #expect(agents[1] == ClaudeAgents.Entry(id: "5ffc161a", sessionId: "5ffc161a-bbbb", kind: "background", cwd: "/g"))
        #expect(ClaudeAgents.parse(Data("not json".utf8)).isEmpty)
    }

    @Test func attachesToTheNewestCandidateRunningInBackground() {
        let agents = ClaudeAgents.parse(sample)
        let target = ClaudeAgents.attachTarget(candidates: ["new-1", "5ffc161a-bbbb", "761fddb3-aaaa"], agents: agents)
        #expect(target?.attachID == "5ffc161a")
        #expect(target?.sessionID == "5ffc161a-bbbb")
    }

    @Test func interactiveOrUnknownSessionsAreResumedAsBefore() {
        let agents = ClaudeAgents.parse(sample)
        #expect(ClaudeAgents.attachTarget(candidates: ["97b8470c-cccc"], agents: agents) == nil)
        #expect(ClaudeAgents.attachTarget(candidates: ["other"], agents: agents) == nil)
        #expect(ClaudeAgents.attachTarget(candidates: ["5ffc161a-bbbb"], agents: []) == nil)
    }

    @Test func attachCommandKeepsOfficeTag() {
        let command = ClaudeLaunch.attachCommand(claudePath: "/c", attachID: "5ffc161a", cwd: "/p", socketPath: "/sock",
                                                 baseEnvironment: ["CLAUDECODE": "1"], tag: "office-1")
        #expect(command.args == ["-l", "-c", "exec '/c' attach '5ffc161a'"])
        #expect(command.currentDirectory == "/p")
        #expect(command.environment["AGENT_OFFICE_SESSION"] == "office-1")
        #expect(command.environment["CLAUDECODE"] == nil)
    }
}
