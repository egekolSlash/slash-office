import Testing
@testable import AgentOfficeCore

@Suite struct ShellPathTests {
    @Test func parsesPathBetweenMarkersIgnoringNoise() {
        let output = "Welcome!\n\u{1b}[1mprompt junk\(ShellPath.beginMarker)/a/bin:/usr/bin\(ShellPath.endMarker)trailing"
        #expect(ShellPath.parse(output) == "/a/bin:/usr/bin")
    }

    @Test func missingMarkersGiveNil() {
        #expect(ShellPath.parse("no markers here") == nil)
        #expect(ShellPath.parse("\(ShellPath.beginMarker)\(ShellPath.endMarker)") == nil)
    }

    @Test func capturesRealLoginShellPath() throws {
        let path = try #require(ShellPath.capture(shell: "/bin/zsh", timeout: 5))
        #expect(path.split(separator: ":").contains("/usr/bin"))
    }

    @Test func unknownShellGivesNil() {
        #expect(ShellPath.capture(shell: "/nonexistent/shell", timeout: 1) == nil)
    }
}
