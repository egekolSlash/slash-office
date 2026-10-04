import Testing
@testable import AgentOfficeCore

@Suite struct AgentStateTests {
    func run(_ events: [AgentEvent], from start: AgentState = .starting) -> AgentState {
        events.reduce(start, AgentStateMachine.reduce)
    }

    @Test func startupBecomesIdle() {
        #expect(run([.sessionStarted(providerSessionID: "x")]) == .idle)
    }

    @Test func fullTurnWithPermission() {
        let events: [AgentEvent] = [
            .sessionStarted(providerSessionID: nil),
            .promptSubmitted(text: "go"),
            .toolStarted(name: "Bash", summary: "ls"),
            .needsInput(.permission("perm")),
        ]
        #expect(run(events) == .waiting(.permission("perm")))
        #expect(run(events + [.toolFinished(name: "Bash", touchedFiles: [])]) == .working(tool: nil))
        #expect(run(events + [.toolFinished(name: "Bash", touchedFiles: []), .turnEnded]) == .idle)
    }

    @Test func toolStartedShowsTool() {
        #expect(run([.promptSubmitted(text: "a"), .toolStarted(name: "Edit", summary: nil)]) == .working(tool: "Edit"))
    }

    @Test func questionThenAnswer() {
        let asked = run([.promptSubmitted(text: "a"), .toolStarted(name: "AskUserQuestion", summary: nil), .needsInput(.question("q"))])
        #expect(asked == .waiting(.question("q")))
        #expect(AgentStateMachine.reduce(asked, .promptSubmitted(text: "b")) == .working(tool: nil))
    }

    @Test func compactionSessionStartDoesNotInterruptWork() {
        #expect(AgentStateMachine.reduce(.working(tool: "Bash"), .sessionStarted(providerSessionID: nil)) == .working(tool: "Bash"))
    }

    @Test func todosDoNotChangeState() {
        #expect(AgentStateMachine.reduce(.working(tool: "X"), .todosChanged([])) == .working(tool: "X"))
    }

    @Test func exitedIsTerminal() {
        let exited = run([.promptSubmitted(text: "a"), .sessionEnded])
        #expect(exited == .exited)
        #expect(AgentStateMachine.reduce(exited, .promptSubmitted(text: "b")) == .exited)
    }
}
