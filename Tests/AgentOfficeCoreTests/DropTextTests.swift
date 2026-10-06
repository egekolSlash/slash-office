import Testing
@testable import AgentOfficeCore

@Suite struct DropTextTests {
    @Test func escapesLikeGhostty() {
        #expect(DropText.text(forPaths: ["/Users/me/Desktop/ekran görüntüsü 1.png"]) == #"/Users/me/Desktop/ekran\ görüntüsü\ 1.png"#)
        #expect(DropText.text(forPaths: ["/tmp/a(1)'s&b.txt"]) == #"/tmp/a\(1\)\'s\&b.txt"#)
        #expect(DropText.text(forPaths: ["/a/b", "/c d/e"]) == #"/a/b /c\ d/e"#)
        #expect(DropText.text(forPaths: []) == "")
    }
}
