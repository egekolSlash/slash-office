import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct AntigravityHooksTests {
    func object(_ data: Data?) throws -> [String: Any] {
        let data = try #require(data)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func addsOurEntryAndKeepsTheUsersHooks() throws {
        let existing = Data(#"{"lint":{"PostToolUse":[{"matcher":"run_command","hooks":[{"command":"./lint.sh"}]}]}}"#.utf8)
        let merged = try object(try AntigravityHooks.merged(existing: existing, hookBinaryPath: "/A B/agent-office-hook"))
        #expect(merged["lint"] != nil)
        let ours = try #require(merged[AntigravityHooks.entryName] as? [String: Any])
        #expect(Set(ours.keys) == ["SessionStart", "PreInvocation", "PreToolUse", "PostToolUse", "Stop"])
        let group = try #require((ours["PreToolUse"] as? [[String: Any]])?.first)
        #expect(group["matcher"] as? String == "*")
        let handler = try #require((group["hooks"] as? [[String: Any]])?.first)
        #expect(handler["command"] as? String == "if [ -x '/A B/agent-office-hook' ]; then exec '/A B/agent-office-hook' antigravity; else cat >/dev/null; fi")
    }

    @Test func unchangedEntryIsNotRewritten() throws {
        let first = try AntigravityHooks.merged(existing: nil, hookBinaryPath: "/h")
        #expect(try AntigravityHooks.merged(existing: first, hookBinaryPath: "/h") == nil)
        // Uygulama taşınınca yol güncellenir.
        #expect(try AntigravityHooks.merged(existing: first, hookBinaryPath: "/moved/h") != nil)
        #expect(try AntigravityHooks.merged(existing: Data("  \n".utf8), hookBinaryPath: "/h") != nil)
    }

    @Test func refusesToOverwriteAFileItCannotRead() {
        #expect(throws: AntigravityHooks.InstallError.unreadable) {
            try AntigravityHooks.merged(existing: Data("{ not json".utf8), hookBinaryPath: "/h")
        }
    }

    /// Hook komutu hiç hata vermez: agy başarısız PreToolUse hook'unda aracı engeller.
    @Test func commandSucceedsEvenWhenTheHelperIsGone() throws {
        let command = AntigravityHooks.command(hookBinaryPath: "/nonexistent/agent-office-hook")
        let result = try #require(ProcessRunner.run("/bin/sh", ["-c", "echo '{\"x\":1}' | { \(command); }"], timeout: 5))
        #expect(result.status == 0 && result.output.isEmpty)
    }

    @Test func installWritesTheFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("config/hooks.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        #expect(try AntigravityHooks.install(at: url, hookBinaryPath: "/h"))
        #expect(try !AntigravityHooks.install(at: url, hookBinaryPath: "/h"))
        #expect(try object(Data(contentsOf: url))[AntigravityHooks.entryName] != nil)
    }
}
