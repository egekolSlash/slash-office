import Darwin
import Testing
@testable import AgentOfficeCore

@Suite struct ShellSessionTests {
    @Test func shellLaunchUsesLoginShellInCwdWithCleanEnvironment() {
        let command = ShellLaunch.command(shellPath: "/bin/zsh", cwd: "/proj", sessionID: "s1",
                                          baseEnvironment: ["CLAUDECODE": "1", "CLAUDE_CODE_X": "y", "AGENT_OFFICE_SOCKET": "/old", "PATH": "/a"])
        #expect(command.executable == "/bin/zsh")
        #expect(command.args == ["-l"])
        #expect(command.currentDirectory == "/proj")
        #expect(command.environment["CLAUDECODE"] == nil && command.environment["CLAUDE_CODE_X"] == nil)
        #expect(command.environment["AGENT_OFFICE_SOCKET"] == nil)
        #expect(command.environment["AGENT_OFFICE_SESSION"] == "s1")
        #expect(command.environment["TERM"] == "xterm-256color" && command.environment["PATH"] == "/a")
    }
}
