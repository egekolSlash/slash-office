import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct GitWorkspaceTests {
    func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ao-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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

    @Test func notARepositoryHasNoHead() throws {
        #expect(GitWorkspace(directory: try tempDir().path).head() == nil)
    }

    @Test func emptyRepositoryHasNoHead() throws {
        let dir = try tempDir()
        try git(dir, "init", "-q", "-b", "main")
        #expect(GitWorkspace(directory: dir.path).head() == nil)
    }

    @Test func diffIncludesModifiedAndUntrackedFiles() throws {
        let dir = try tempDir()
        try git(dir, "init", "-q", "-b", "main")
        try "one\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(dir, "add", ".")
        try git(dir, "commit", "-q", "-m", "init")
        let workspace = GitWorkspace(directory: dir.path)
        let baseline = try #require(workspace.head())
        #expect(workspace.branch() == "main")

        try "one\ntwo\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Klasör Adı"), withIntermediateDirectories: true)
        try "yeni\n".write(to: dir.appendingPathComponent("Klasör Adı/ş.txt"), atomically: true, encoding: .utf8)

        let files = DiffParser.parse(workspace.diff(since: baseline))
        let byPath = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0) })
        #expect(byPath["a.txt"]?.change == .modified && byPath["a.txt"]?.additions == 1)
        #expect(byPath["Klasör Adı/ş.txt"]?.change == .added && byPath["Klasör Adı/ş.txt"]?.additions == 1)
    }

    @Test func committedChangesSinceBaselineAreIncluded() throws {
        let dir = try tempDir()
        try git(dir, "init", "-q", "-b", "main")
        try "x\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(dir, "add", ".")
        try git(dir, "commit", "-q", "-m", "init")
        let workspace = GitWorkspace(directory: dir.path)
        let baseline = try #require(workspace.head())
        try "x\ny\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(dir, "commit", "-qam", "agent commit")
        // Ajan commit etse de oturum başından beri olan değişiklik görünmeli.
        #expect(DiffParser.parse(workspace.diff(since: baseline)).first?.path == "a.txt")
    }

    func committedRepo() throws -> (URL, GitWorkspace) {
        let dir = try tempDir()
        try git(dir, "init", "-q", "-b", "main")
        try "one\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "keep\n".write(to: dir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try git(dir, "add", ".")
        try git(dir, "commit", "-q", "-m", "init")
        return (dir, GitWorkspace(directory: dir.path))
    }

    @Test func statusSeparatesStagedUnstagedAndUntracked() throws {
        let (dir, workspace) = try committedRepo()
        try "one\ntwo\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(dir, "add", "a.txt")
        try "one\ntwo\nthree\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: dir.appendingPathComponent("b.txt"))
        try "new\n".write(to: dir.appendingPathComponent("Yeni Dosya ş.txt"), atomically: true, encoding: .utf8)
        let status = Dictionary(uniqueKeysWithValues: workspace.status().map { ($0.path, $0) })
        #expect(status["a.txt"]?.staged == .modified && status["a.txt"]?.unstaged == .modified)
        #expect(status["b.txt"]?.staged == nil && status["b.txt"]?.unstaged == .deleted)
        #expect(status["Yeni Dosya ş.txt"]?.unstaged == .untracked)
    }

    @Test func unstagedAndStagedDiffsAreSeparateAndEmptyAfterCommit() throws {
        let (dir, workspace) = try committedRepo()
        try "one\ntwo\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(dir, "add", "a.txt")
        try "x\n".write(to: dir.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        #expect(DiffParser.parse(workspace.diff(.staged)).map(\.path) == ["a.txt"])
        #expect(DiffParser.parse(workspace.diff(.unstaged)).map(\.path) == ["c.txt"])
        try git(dir, "add", ".")
        try git(dir, "commit", "-q", "-m", "second")
        #expect(DiffParser.parse(workspace.diff(.staged)).isEmpty)
        #expect(DiffParser.parse(workspace.diff(.unstaged)).isEmpty)
        #expect(workspace.status().isEmpty)
    }

    @Test func snapshotDiffShowsOnlyLaterChangesAndKeepsIndex() throws {
        let (dir, workspace) = try committedRepo()
        try "earlier\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(dir, "add", "a.txt")
        let stagedBefore = workspace.diff(.staged)
        let tree = try #require(workspace.snapshotTree())
        #expect(workspace.diff(.staged) == stagedBefore)   // kullanıcının index'i değişmedi
        try "later\n".write(to: dir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try "brand new\n".write(to: dir.appendingPathComponent("n.txt"), atomically: true, encoding: .utf8)
        let paths = Set(DiffParser.parse(workspace.diff(.since(tree: tree))).map(\.path))
        #expect(paths == ["b.txt", "n.txt"])
    }

    @Test func freshRepositoryWithoutCommitsStillReportsStatus() throws {
        let dir = try tempDir()
        try git(dir, "init", "-q", "-b", "main")
        try "x\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let workspace = GitWorkspace(directory: dir.path)
        #expect(workspace.status().first?.unstaged == .untracked)
        #expect(DiffParser.parse(workspace.diff(.unstaged)).first?.path == "a.txt")
        #expect(workspace.snapshotTree() != nil)
    }

    @Test func notARepositoryHasNoStatusOrSnapshot() throws {
        let workspace = GitWorkspace(directory: try tempDir().path)
        #expect(workspace.status().isEmpty)
        #expect(workspace.snapshotTree() == nil)
        #expect(workspace.isRepository == false)
    }
}
