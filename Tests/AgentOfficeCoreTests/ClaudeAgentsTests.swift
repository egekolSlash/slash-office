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
        #expect(agents[1] == ClaudeAgents.Entry(id: "5ffc161a", sessionId: "5ffc161a-bbbb", kind: "background", cwd: "/g",
                                                pid: 72977, state: "working", status: "busy"))
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

    @Test func parsesPidAndState() {
        let entry = ClaudeAgents.parse(sample)[1]
        #expect(entry.pid == 72977 && entry.state == "working" && entry.status == "busy")
    }

    @Test func listedStateMapsToCoarseState() {
        func e(_ state: String?, _ status: String? = nil) -> ClaudeAgents.Entry {
            .init(id: "x", sessionId: "x", kind: "background", state: state, status: status)
        }
        #expect(ClaudeAgents.state(of: e("working")) == .working(tool: nil))
        #expect(ClaudeAgents.state(of: e("done")) == .idle)
        #expect(ClaudeAgents.state(of: e("blocked"))?.stateClass == AgentState.waiting(.question("")).stateClass)
        #expect(ClaudeAgents.state(of: e(nil, "busy")) == .working(tool: nil))
        #expect(ClaudeAgents.state(of: e("mystery")) == nil)
    }

    /// Hook kaçtıysa (ör. "bitti" başka bir sürece gitti) liste düzeltir; aynı sınıfta hook'un ayrıntısı kalır.
    @Test func correctionOnlyOnClassMismatchOrDisappearance() {
        let done = ClaudeAgents.Entry(id: "a", sessionId: "a", kind: "background", state: "done")
        let working = ClaudeAgents.Entry(id: "a", sessionId: "a", kind: "background", state: "working")
        #expect(ClaudeAgents.correction(current: .working(tool: "Bash"), entry: done) == .idle)
        #expect(ClaudeAgents.correction(current: .working(tool: "Bash"), entry: working) == nil)
        #expect(ClaudeAgents.correction(current: .idle, entry: nil) == .exited)
        #expect(ClaudeAgents.correction(current: .exited, entry: nil) == nil)
    }

    /// Terminalde `/resume` ile arka plandaki oturuma bağlanan `claude` listede yok: izleyici, çalışıyor sayılmaz.
    @Test func viewerIsAClaudeProcessMissingFromTheList() {
        let agents = ClaudeAgents.parse(sample)
        let seen = Date(timeIntervalSince1970: 100)
        #expect(ClaudeAgents.isViewer(pid: 76460, seenAt: seen, listedAt: seen.addingTimeInterval(5), agents: agents))
        #expect(!ClaudeAgents.isViewer(pid: 74016, seenAt: seen, listedAt: seen.addingTimeInterval(5), agents: agents))
        // Yeni açılan claude henüz listeye yazılmamış olabilir: erken alınmış liste karar vermez.
        #expect(!ClaudeAgents.isViewer(pid: 76460, seenAt: seen, listedAt: seen.addingTimeInterval(1), agents: agents))
        #expect(!ClaudeAgents.isViewer(pid: 76460, seenAt: seen, listedAt: nil, agents: agents))
    }
}
