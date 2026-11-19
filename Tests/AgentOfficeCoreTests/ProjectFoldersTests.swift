import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct ProjectFoldersTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("roots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func scanListsSubfoldersByNameSkippingHiddenFilesAndPackages() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["web10", "web2", "Api", ".hidden", "Tool.app"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data().write(to: root.appendingPathComponent("notes.txt"))
        let other = try makeRoot()
        defer { try? FileManager.default.removeItem(at: other) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: other)

        let names = ProjectFolders.scan(root.path).map { ($0 as NSString).lastPathComponent }
        #expect(names == ["Api", "linked", "web2", "web10"])
        #expect(ProjectFolders.scan(root.path + "/").first == root.appendingPathComponent("Api").path)
    }

    @Test func scanOfMissingRootIsEmpty() {
        #expect(ProjectFolders.scan("/no/such/folder-\(UUID().uuidString)").isEmpty)
    }

    @Test func newFolderAppearsOnRescan() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ProjectFolders.scan(roots: [root.path]).isEmpty)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("fresh"), withIntermediateDirectories: true)
        #expect(ProjectFolders.scan(roots: [root.path, root.path]) == [root.appendingPathComponent("fresh").path])
    }

    @Test func mergedPutsRecentFirstWithoutDuplicates() {
        let merged = ProjectFolders.merged(recent: ["/git/b", "/elsewhere/x"], discovered: ["/git/a", "/git/b/", "/git/c"])
        #expect(merged == ["/git/b", "/elsewhere/x", "/git/a", "/git/c"])
    }

    @Test func addingRootIsUniqueAndNormalized() {
        #expect(ProjectFolders.adding("/git/", to: ["/work"]) == ["/work", "/git"])
        #expect(ProjectFolders.adding("/git", to: ["/git"]) == ["/git"])
    }
}
