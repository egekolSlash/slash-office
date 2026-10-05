import Testing
@testable import AgentOfficeCore

@Suite struct RecentProjectsTests {
    @Test func addingMovesToFrontWithoutDuplicates() {
        let list = RecentProjects.adding("/a/", to: ["/b", "/a", "/c"])
        #expect(list == ["/a", "/b", "/c"])
    }

    @Test func addingCapsAtLimit() {
        let list = (0..<RecentProjects.limit).map { "/p\($0)" }
        #expect(RecentProjects.adding("/new", to: list).count == RecentProjects.limit)
        #expect(RecentProjects.adding("/new", to: list).first == "/new")
    }

    @Test func filterPrefersNameMatches() {
        let list = ["/git/room-logic-worktree1", "/room-logic/other", "/git/juice-merge"]
        #expect(RecentProjects.filter(list, query: "room-logic") == ["/git/room-logic-worktree1", "/room-logic/other"])
        #expect(RecentProjects.filter(list, query: " ") == list)
    }
}
