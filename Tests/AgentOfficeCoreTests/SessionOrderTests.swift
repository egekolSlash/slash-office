import Foundation
import Testing
@testable import AgentOfficeCore

@MainActor
@Suite struct SessionOrderTests {
    private func item(_ id: String, name: String? = nil, project: String = "p", state: AgentState = .idle,
                      at seconds: Double? = nil, heat: Double = 0) -> SessionOrder.Item {
        SessionOrder.Item(id: id, name: name ?? id, project: project, state: state,
                          lastActive: seconds.map(Date.init(timeIntervalSince1970:)), heat: heat)
    }

    @Test func manualKeepsGivenOrder() {
        let items = [item("b"), item("a"), item("c")]
        #expect(SessionOrder.sorted(items, by: .manual) == ["b", "a", "c"])
    }

    @Test func activityThenRecencyThenManual() {
        let items = [item("x"), item("hot", heat: 0.9), item("new", at: 50), item("old", at: 10), item("warm", heat: 0.4)]
        #expect(SessionOrder.sorted(items, by: .activity) == ["hot", "warm", "new", "old", "x"])
    }

    @Test func recentPutsSessionsWithoutEventsLast() {
        let items = [item("none"), item("old", at: 10), item("new", at: 50)]
        #expect(SessionOrder.sorted(items, by: .recent) == ["new", "old", "none"])
    }

    @Test func projectGroupsThenNames() {
        let items = [item("1", name: "web", project: "zeta"), item("2", name: "api", project: "Alpha"),
                     item("3", name: "cli", project: "zeta"), item("4", name: "app", project: "Alpha")]
        #expect(SessionOrder.sorted(items, by: .project) == ["2", "4", "3", "1"])
    }

    @Test func nameUsesNaturalOrder() {
        let items = [item("a", name: "task10"), item("b", name: "task2"), item("c", name: "Task1")]
        #expect(SessionOrder.sorted(items, by: .name) == ["c", "b", "a"])
    }

    @Test func statusPutsWaitingFirstAndStoppedLast() {
        let items = [item("off", state: .exited), item("idle"), item("busy", state: .working(tool: nil)),
                     item("ask", state: .waiting(.permission("Bash")))]
        #expect(SessionOrder.sorted(items, by: .status) == ["ask", "busy", "idle", "off"])
    }

    @Test func movingMatchesListOnMove() {
        let ids = ["a", "b", "c", "d"]
        #expect(SessionOrder.moving(ids, from: [0], to: 3) == ["b", "c", "a", "d"])
        #expect(SessionOrder.moving(ids, from: [3], to: 0) == ["d", "a", "b", "c"])
        #expect(SessionOrder.moving(ids, from: [1, 2], to: 4) == ["a", "d", "b", "c"])
        #expect(SessionOrder.moving(ids, from: [2], to: 2) == ids)
    }

    @Test func storeReorderKeepsUnlistedAtEnd() {
        let store = AgentStore()
        for id in ["a", "b", "c", "d"] { store.register(id: id, title: id, cwd: "/\(id)") }
        store.reorder(["c", "a", "ghost"])
        #expect(store.sessions.map(\.id) == ["c", "a", "b", "d"])
    }

    @Test func recordsLoadInListOrderThenCreation() {
        func record(_ id: String, index: Int?, created: Double) -> SessionRecord {
            var record = SessionRecord(id: id, title: id, cwd: "/", claudeSessionID: nil, createdAt: Date(timeIntervalSince1970: created))
            record.listIndex = index
            return record
        }
        let records = [record("old", index: nil, created: 1), record("second", index: 1, created: 5),
                       record("first", index: 0, created: 9), record("older", index: nil, created: 0)]
        #expect(records.sorted(by: SessionRecord.listOrder).map(\.id) == ["first", "second", "older", "old"])
    }
}
