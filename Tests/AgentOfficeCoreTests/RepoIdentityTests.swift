import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct RepoIdentityTests {
    func tempDir() throws -> URL {
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent("ao-room-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        // git `/private/var/...` döndürür; karşılaştırma için gerçek yol.
        return URL(fileURLWithPath: String(cString: realpath(raw.path, nil)))
    }

    @discardableResult
    func git(_ dir: URL, _ args: String...) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", dir.path, "-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false"] + args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test func worktreeSharesRoomWithMainRepository() throws {
        let root = try tempDir()
        let main = root.appendingPathComponent("juice-merge")
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        try git(main, "init", "-q")
        try git(main, "commit", "-q", "--allow-empty", "-m", "init")
        let worktree = root.appendingPathComponent("juice-merge-worktree1")
        #expect(try git(main, "worktree", "add", "-q", worktree.path) == 0)
        let sub = main.appendingPathComponent("Assets")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        #expect(RepoIdentity.roomKey(for: main.path) == main.path)
        #expect(RepoIdentity.roomKey(for: worktree.path) == main.path)
        #expect(RepoIdentity.roomKey(for: sub.path) == main.path)
        #expect(RepoIdentity.worktreeName(directory: worktree.path, roomKey: main.path) == "juice-merge-worktree1")
        #expect(RepoIdentity.worktreeName(directory: main.path, roomKey: main.path) == nil)
        #expect(RepoIdentity.worktreeName(directory: sub.path, roomKey: main.path) == nil)
    }

    @Test func nonRepositoryIsItsOwnRoom() throws {
        let dir = try tempDir()
        #expect(RepoIdentity.roomKey(for: dir.path) == dir.path)
    }

    @Test func missingDirectoryIsItsOwnRoom() {
        #expect(RepoIdentity.roomKey(for: "/nope/does-not-exist") == "/nope/does-not-exist")
    }
}
