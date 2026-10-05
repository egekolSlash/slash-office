import Testing
@testable import AgentOfficeCore

@Suite struct ProjectPaletteTests {
    @Test func paletteIsStableAndDistinguishesSameNameDifferentPath() {
        let first = ProjectPalette.index(for: "/Users/me/git/juice-merge")
        #expect(first == ProjectPalette.index(for: "/Users/me/git/juice-merge"))
        #expect((0..<ProjectPalette.colors.count).contains(first))
        #expect(ProjectPalette.index(for: "/Users/me/git/a/app") != ProjectPalette.index(for: "/Users/me/git/b/app"))
    }
}
