import Foundation
import Testing
@testable import AgentOfficeCore

@MainActor
@Suite struct AgentStoreTests {
    @Test func registerKeepsOrder() {
        let store = AgentStore()
        store.register(id: "a", title: "A", cwd: "/a")
        store.register(id: "b", title: "B", cwd: "/b")
        #expect(store.sessions.map(\.id) == ["a", "b"])
        #expect(store.session("a")?.state == .starting)
    }

    @Test func applyUpdatesStateAndDetails() {
        let store = AgentStore()
        store.register(id: "a", title: "A", cwd: "/a")
        let date = Date(timeIntervalSince1970: 100)
        store.apply([
            .sessionStarted(providerSessionID: "p1"),
            .promptSubmitted(text: "hello"),
            .toolStarted(name: "TodoWrite", summary: nil),
            .todosChanged([TodoItem(title: "t", status: .pending)]),
        ], to: "a", at: date)
        let session = store.session("a")
        #expect(session?.state == .working(tool: "TodoWrite"))
        #expect(session?.providerSessionID == "p1")
        #expect(session?.lastPrompt == "hello")
        #expect(session?.todos == [TodoItem(title: "t", status: .pending)])
        #expect(session?.lastEventAt == date)
    }

    @Test func unknownSessionIsIgnored() {
        let store = AgentStore()
        store.apply([.promptSubmitted(text: "x")], to: "ghost")
        #expect(store.sessions.isEmpty)
    }

    @Test func waitingCountAndExit() {
        let store = AgentStore()
        store.register(id: "a", title: "A", cwd: "/a")
        store.register(id: "b", title: "B", cwd: "/b")
        store.apply([.needsInput(.permission("p"))], to: "a")
        #expect(store.waitingCount == 1)
        store.markExited("a")
        #expect(store.session("a")?.state == .exited)
        #expect(store.waitingCount == 0)
        store.remove("a")
        #expect(store.sessions.map(\.id) == ["b"])
    }
}
