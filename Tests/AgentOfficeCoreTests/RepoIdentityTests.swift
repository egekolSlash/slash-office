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
        #expect(RepoIdentity.locate(worktree.path).worktree == "juice-merge-worktree1")
        #expect(RepoIdentity.locate(main.path).worktree == nil)
        #expect(RepoIdentity.locate(sub.path).worktree == nil)
    }

    @Test func nonRepositoryIsItsOwnRoom() throws {
        let dir = try tempDir()
        #expect(RepoIdentity.roomKey(for: dir.path) == dir.path)
    }

    @Test func missingDirectoryIsItsOwnRoom() {
        #expect(RepoIdentity.roomKey(for: "/nope/does-not-exist") == "/nope/does-not-exist")
    }

    @Test func worktreeNestedInsideRepositoryIsLabelled() throws {
        let root = try tempDir()
        let main = root.appendingPathComponent("juice-merge")
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        try git(main, "init", "-q")
        try git(main, "commit", "-q", "--allow-empty", "-m", "init")
        let nested = main.appendingPathComponent(".claude/worktrees/foo")
        #expect(try git(main, "worktree", "add", "-q", nested.path) == 0)
        let identity = RepoIdentity.locate(nested.path)
        #expect(identity.roomKey == main.path)
        #expect(identity.worktree == "foo")
        #expect(RepoIdentity.locate(main.appendingPathComponent("Assets").path).worktree == nil)
        #expect(RepoIdentity.locate(main.path) == RepoIdentity.Identity(roomKey: main.path, worktree: nil))
    }

    @Test func symlinkedMainRepositoryIsNotAWorktree() throws {
        let root = try tempDir()
        let main = root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        try git(main, "init", "-q")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: main)
        #expect(RepoIdentity.locate(link.path).worktree == nil)
    }
}
