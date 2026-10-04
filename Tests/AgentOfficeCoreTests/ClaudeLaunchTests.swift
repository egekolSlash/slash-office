import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct ClaudeLaunchTests {
    @Test func locatorFindsExecutableInLaterDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let empty = root.appendingPathComponent("empty"), bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let tool = bin.appendingPathComponent("claude")
        FileManager.default.createFile(atPath: tool.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        #expect(ExecutableLocator.find("claude", searchDirectories: [empty.path, bin.path]) == tool.path)
        #expect(ExecutableLocator.find("nope", searchDirectories: [empty.path, bin.path]) == nil)
    }

    @Test func defaultDirectoriesIncludeLocalBinFirst() {
        let dirs = ExecutableLocator.defaultDirectories(home: "/Users/me", pathVariable: "/usr/bin:/bin")
        #expect(dirs.first == "/Users/me/.local/bin")
        #expect(dirs.contains("/opt/homebrew/bin"))
        #expect(dirs.suffix(2) == ["/usr/bin", "/bin"])
    }

    @Test func shellQuoteHandlesSpacesAndQuotes() {
        #expect(ClaudeLaunch.shellQuote("/Users/me/Library/Application Support/x") == "'/Users/me/Library/Application Support/x'")
        #expect(ClaudeLaunch.shellQuote("it's") == #"'it'\''s'"#)
    }

    @Test func settingsRegisterEveryHookEvent() throws {
        let data = ClaudeLaunch.settingsJSON(hookCommand: "'/a b/agent-office-hook' claude")
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        for event in ClaudeLaunch.hookEvents {
            let entry = value["hooks"]?[event]?.array?.first
            #expect(entry?["hooks"]?.array?.first?["command"]?.string == "'/a b/agent-office-hook' claude")
        }
        #expect(value["hooks"]?["PreToolUse"]?.array?.first?["matcher"]?.string == "*")
        #expect(Set(ClaudeLaunch.hookEvents) == ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"])
    }

    @Test func newAndResumeCommands() {
        let new = ClaudeLaunch.command(claudePath: "/Users/me/.local/bin/claude", sessionID: "1111", resume: false,
                                       settingsPath: "/S p/s.json", cwd: "/proj", socketPath: "/sock",
                                       baseEnvironment: ["HOME": "/Users/me", "TERM": "dumb"])
        #expect(new.executable == "/bin/zsh")
        #expect(new.args == ["-l", "-c", "exec '/Users/me/.local/bin/claude' --session-id '1111' --settings '/S p/s.json'"])
        #expect(new.currentDirectory == "/proj")
        #expect(new.environment["TERM"] == "xterm-256color")
        #expect(new.environment["COLORTERM"] == "truecolor")
        #expect(new.environment["AGENT_OFFICE_SESSION"] == "1111")
        #expect(new.environment["AGENT_OFFICE_SOCKET"] == "/sock")
        #expect(new.environment["HOME"] == "/Users/me")
        #expect(new.environmentList.contains("AGENT_OFFICE_SESSION=1111"))

        let resumed = ClaudeLaunch.command(claudePath: "/c", sessionID: "1111", resume: true,
                                           settingsPath: "/s", cwd: "/proj", socketPath: "/sock", baseEnvironment: [:])
        #expect(resumed.args.last == "exec '/c' --resume '1111' --settings '/s'")
    }

    @Test func resumeUsesClaudeSessionIDButKeepsOfficeTag() {
        let command = ClaudeLaunch.command(claudePath: "/c", sessionID: "claude-2", resume: true, settingsPath: "/s",
                                           cwd: "/p", socketPath: "/sock", baseEnvironment: [:], tag: "office-1")
        #expect(command.args.last == "exec '/c' --resume 'claude-2' --settings '/s'")
        #expect(command.environment["AGENT_OFFICE_SESSION"] == "office-1")
    }

    @Test func launchEnvironmentDropsParentAgentVariables() {
        let command = ClaudeLaunch.command(claudePath: "/c", sessionID: "s", resume: false, settingsPath: "/x", cwd: "/p",
                                           socketPath: "/sock",
                                           baseEnvironment: ["CLAUDECODE": "1", "CLAUDE_CODE_ENTRYPOINT": "cli",
                                                             "AGENT_OFFICE_SESSION": "parent", "HOME": "/h", "PATH": "/a:/b"])
        #expect(command.environment["CLAUDECODE"] == nil)
        #expect(command.environment["CLAUDE_CODE_ENTRYPOINT"] == nil)
        #expect(command.environment["AGENT_OFFICE_SESSION"] == "s")
        #expect(command.environment["HOME"] == "/h")
        #expect(command.environment["PATH"] == "/a:/b")
    }

    @Test func defaultDirectoriesCoverCommonInstallers() {
        let dirs = ExecutableLocator.defaultDirectories(home: "/Users/me", pathVariable: nil)
        for dir in ["/Users/me/.claude/local", "/Users/me/.bun/bin", "/Users/me/.volta/bin", "/Users/me/.npm-global/bin"] {
            #expect(dirs.contains(dir))
        }
    }
}
