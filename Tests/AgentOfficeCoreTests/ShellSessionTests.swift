import Darwin
import Foundation
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

    @Test func zshIntegrationPutsWrapperFirstAfterUserFilesResetPath() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: String(cString: realpath(fm.temporaryDirectory.path, nil)))
            .appendingPathComponent(UUID().uuidString).path
        let home = root + "/home"
        try fm.createDirectory(atPath: home, withIntermediateDirectories: true)
        // Kullanıcının dosyaları PATH'i baştan yazar; ZDOTDIR'e göre yazılmış bir değişken de bırakır.
        try "export FROM_ENV=1\n".write(toFile: home + "/.zshenv", atomically: true, encoding: .utf8)
        try "export PATH=/usr/bin:/bin\nexport SEEN_ZDOTDIR=\"${ZDOTDIR:-$HOME}\"\n".write(toFile: home + "/.zshrc", atomically: true, encoding: .utf8)
        let integration = ShellIntegration(binDirectory: root + "/bin", zdotDirectory: root + "/zdotdir",
                                           claudePath: "/usr/bin/true", settingsPath: root + "/s.json", socketPath: root + "/sock")
        try integration.install()
        var command = ShellLaunch.command(shellPath: "/bin/zsh", cwd: home, sessionID: "s1",
                                          baseEnvironment: ["HOME": home, "PATH": "/usr/bin:/bin"], integration: integration)
        command.args += ["-i", "-c", #"print -r -- "$(whence -p claude)|$FROM_ENV|$SEEN_ZDOTDIR|$ZDOTDIR|${HISTFILE:-$HOME/.zsh_history}""#]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.args
        process.environment = command.environment
        process.currentDirectoryURL = URL(fileURLWithPath: home)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "\(root)/bin/claude|1|\(home)|\(home)|\(home)/.zsh_history")
        #expect(command.environment["AGENT_OFFICE_SOCKET"] == root + "/sock")
    }

    @Test func shellIsIdleWhenShellOwnsForeground() {
        #expect(ShellActivity.state(shellPID: 100, foregroundGroup: 100, commandName: "zsh") == .idle)
    }

    @Test func shellIsWorkingWhenAnotherGroupOwnsForeground() {
        #expect(ShellActivity.state(shellPID: 100, foregroundGroup: 200, commandName: "npm") == .working(tool: "npm"))
    }

    @Test func unreadableForegroundCountsAsIdle() {
        #expect(ShellActivity.state(shellPID: 100, foregroundGroup: nil, commandName: nil) == .idle)
        #expect(ShellActivity.foregroundGroup(ptyFD: -1) == nil)
    }

    @Test func claudeVersionBinaryShownAsClaude() {
        #expect(ShellActivity.displayName("2.1.289", executablePath: "/Users/x/.local/share/claude/versions/2.1.289") == "claude")
        #expect(ShellActivity.displayName("npm", executablePath: "/opt/homebrew/bin/npm") == "npm")
        #expect(ShellActivity.displayName("vim", executablePath: nil) == "vim")
    }

    @Test func processNameOfSelf() {
        #expect(ShellActivity.processName(getpid())?.isEmpty == false)
        #expect(ShellActivity.processName(-1) == nil)
    }
}
