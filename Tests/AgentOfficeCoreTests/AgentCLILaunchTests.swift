import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct AgentCLILaunchTests {
    @Test func kindsMapToTheirCLIsAndHookProviders() {
        #expect(AgentCLI.candidates(for: .codex) == [.codex])
        // Gemini seçeneği önce Antigravity CLI'ı (agy) dener.
        #expect(AgentCLI.candidates(for: .gemini) == [.antigravity, .gemini])
        #expect(AgentCLI.candidates(for: .claude).isEmpty && AgentCLI.candidates(for: .shell).isEmpty)
        #expect(AgentCLI.antigravity.executableName == "agy")
        #expect(AgentCLI.gemini.hookProvider == nil)
        #expect(SessionKind.codex.accepts(hookProvider: "codex") && !SessionKind.codex.accepts(hookProvider: "claude"))
        #expect(SessionKind.gemini.accepts(hookProvider: "antigravity"))
        #expect(SessionKind.shell.accepts(hookProvider: "claude") && !SessionKind.shell.accepts(hookProvider: "codex"))
        #expect(!SessionKind.shell.isAgent && SessionKind.codex.isAgent && SessionKind.gemini.isAgent)
    }

    @Test func codexStartsWithPerSessionHooks() {
        let command = AgentCLILaunch.command(cli: .codex, executablePath: "/opt/homebrew/bin/codex", resume: false,
                                             hookCommand: "'/A B/agent-office-hook' codex", socketPath: "/s.sock",
                                             cwd: "/p", baseEnvironment: ["CLAUDECODE": "1"], tag: "s1")
        let script = command.args[2]
        #expect(command.executable == "/bin/zsh" && command.currentDirectory == "/p")
        #expect(script.hasPrefix("exec '/opt/homebrew/bin/codex' '-c' "))
        for event in AgentCLILaunch.codexHookEvents { #expect(script.contains("hooks.\(event)=")) }
        // Komut her oturumda aynı: Codex'teki onay kalıcı kalsın, oturum kimliği ortamdan gelsin.
        #expect(script.contains(#"command="'\''/A B/agent-office-hook'\'' codex""#))
        #expect(command.environment["AGENT_OFFICE_SESSION"] == "s1")
        #expect(command.environment["AGENT_OFFICE_SOCKET"] == "/s.sock")
        #expect(command.environment["CLAUDECODE"] == nil)
    }

    @Test func codexHookOverrideIsValidTOMLForThePath() {
        let value = AgentCLILaunch.codexHookOverrides(hookCommand: #"'/x/"q"\y' codex"#)[0]
        #expect(value == #"hooks.SessionStart=[{matcher="*",hooks=[{type="command",command="'/x/\"q\"\\y' codex",timeout=3}]}]"#)
    }

    @Test func withoutHooksThereIsNoSocket() {
        let command = AgentCLILaunch.command(cli: .gemini, executablePath: "/bin/gemini", resume: false,
                                             socketPath: "/s.sock", cwd: "/p", baseEnvironment: [:], tag: "s")
        #expect(command.args[2] == "exec '/bin/gemini'")
        #expect(command.environment["AGENT_OFFICE_SOCKET"] == nil)
    }

    @Test func antigravityGetsTheSocketItsGlobalHookUses() {
        let command = AgentCLILaunch.command(cli: .antigravity, executablePath: "/bin/agy", resume: false,
                                             hookCommand: "'/h' antigravity", socketPath: "/s.sock",
                                             cwd: "/p", baseEnvironment: [:], tag: "s")
        #expect(command.args[2] == "exec '/bin/agy'")
        #expect(command.environment["AGENT_OFFICE_SOCKET"] == "/s.sock")
    }

    @Test func resumeUsesTheKnownSessionOrTheLastOne() {
        #expect(AgentCLILaunch.resumeArguments(for: .codex, sessionID: "019e-1") == ["resume", "019e-1"])
        #expect(AgentCLILaunch.resumeArguments(for: .codex, sessionID: nil) == ["resume", "--last"])
        #expect(AgentCLILaunch.resumeArguments(for: .antigravity, sessionID: "c1") == ["--conversation", "c1"])
        #expect(AgentCLILaunch.resumeArguments(for: .antigravity, sessionID: nil) == ["--continue"])
        #expect(AgentCLILaunch.resumeArguments(for: .gemini, sessionID: "x") == ["--resume", "latest"])
        let script = AgentCLILaunch.command(cli: .codex, executablePath: "/bin/codex", resume: true, sessionID: "019e-1",
                                            hookCommand: "h codex", cwd: "/p", baseEnvironment: [:], tag: "s").args[2]
        #expect(script.contains("'/bin/codex' 'resume' '019e-1' '-c' "))
        // Yedek yeni oturum da hook'larla açılır.
        #expect(script.contains("then exec '/bin/codex' '-c' "))
    }

    /// Betik gerçek zsh'te: devam edecek oturum yoksa (hemen hata) yenisi açılır, normal kapanış olduğu gibi döner.
    @Test func resumeScriptRunsInZsh() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let tool = dir.appendingPathComponent("fake")
        try "#!/bin/sh\nif [ \"$1\" = \"--conversation\" ]; then exit 1; fi\necho fresh\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let command = AgentCLILaunch.command(cli: .antigravity, executablePath: tool.path, resume: true, sessionID: "gone",
                                             cwd: dir.path, baseEnvironment: ["PATH": "/usr/bin:/bin"], tag: "s")
        let result = try #require(ProcessRunner.run("/bin/zsh", ["-f", "-c", command.args[2]], environment: command.environment, timeout: 5))
        #expect(result.status == 0)
        #expect(result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "fresh")
    }
}
