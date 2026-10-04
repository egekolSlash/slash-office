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
}
