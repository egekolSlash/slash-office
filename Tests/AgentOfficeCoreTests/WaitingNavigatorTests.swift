import Testing
@testable import AgentOfficeCore

@Suite struct WaitingNavigatorTests {
    let ids = ["a", "b", "c", "d"]

    @Test func picksNextWaitingAfterCurrentAndWraps() {
        let waiting: Set = ["a", "c"]
        #expect(WaitingNavigator.next(after: "a", ids: ids, isWaiting: waiting.contains) == "c")
        #expect(WaitingNavigator.next(after: "c", ids: ids, isWaiting: waiting.contains) == "a")
        #expect(WaitingNavigator.next(after: "d", ids: ids, isWaiting: waiting.contains) == "a")
        #expect(WaitingNavigator.next(after: nil, ids: ids, isWaiting: waiting.contains) == "a")
    }

    @Test func singleWaitingIsReturnedEvenIfCurrent() {
        #expect(WaitingNavigator.next(after: "b", ids: ids, isWaiting: { $0 == "b" }) == "b")
    }

    @Test func noWaitingGivesNil() {
        #expect(WaitingNavigator.next(after: "a", ids: ids, isWaiting: { _ in false }) == nil)
        #expect(WaitingNavigator.next(after: nil, ids: [], isWaiting: { _ in true }) == nil)
    }

    @Test func unknownCurrentStartsFromBeginning() {
        #expect(WaitingNavigator.next(after: "zzz", ids: ids, isWaiting: { $0 == "d" }) == "d")
    }
}
