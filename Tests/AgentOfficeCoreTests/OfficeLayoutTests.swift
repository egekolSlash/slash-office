import Testing
@testable import AgentOfficeCore

@Suite struct OfficeLayoutTests {
    @Test func groupsByProjectInFirstSeenOrder() {
        let placements = OfficeLayout.place([
            (id: "1", project: "/a"), (id: "2", project: "/b"), (id: "3", project: "/a"),
        ])
        #expect(placements == [
            TilePlacement(id: "1", column: 0, row: 0, project: "/a"),
            TilePlacement(id: "3", column: 1, row: 0, project: "/a"),
            TilePlacement(id: "2", column: 0, row: 1, project: "/b"),
        ])
    }

    @Test func wrapsLongProjectsOntoNextRow() {
        let sessions = (1...6).map { (id: "\($0)", project: "/a") } + [(id: "x", project: "/b")]
        let placements = OfficeLayout.place(sessions, maxPerRow: 4)
        #expect(placements.map(\.row) == [0, 0, 0, 0, 1, 1, 2])
        #expect(placements.map(\.column) == [0, 1, 2, 3, 0, 1, 0])
        #expect(OfficeLayout.gridSize(placements) == (columns: 4, rows: 3))
    }

    @Test func emptyOffice() {
        #expect(OfficeLayout.place([]).isEmpty)
        #expect(OfficeLayout.gridSize([]) == (columns: 0, rows: 0))
    }

    @Test func manySessionsStayWithinColumnLimit() {
        let sessions = (0..<12).map { (id: "\($0)", project: "/p\($0 % 3)") }
        let placements = OfficeLayout.place(sessions)
        #expect(placements.allSatisfy { $0.column < 4 })
        #expect(Set(placements.map { "\($0.column),\($0.row)" }).count == 12)
    }

    @Test func paletteIsStableAndDistinguishesSameNameDifferentPath() {
        let first = ProjectPalette.index(for: "/Users/me/git/juice-merge")
        #expect(first == ProjectPalette.index(for: "/Users/me/git/juice-merge"))
        #expect((0..<ProjectPalette.colors.count).contains(first))
        #expect(ProjectPalette.index(for: "/Users/me/git/a/app") != ProjectPalette.index(for: "/Users/me/git/b/app"))
    }
}
