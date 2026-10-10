import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct FileKindTests {
    @Test func imagesAreRecognizedByExtension() {
        for path in ["a.png", "Assets/ikon.JPG", "b.jpeg", "c.gif", "d.heic", "e.webp", "f.svg", "g.tiff"] {
            #expect(FileKind.isImage(path), "\(path)")
        }
        for path in ["a.swift", "README.md", "Makefile", "data.json", "noext"] {
            #expect(!FileKind.isImage(path), "\(path)")
        }
    }

    /// Terminalde ⌘-tıklanan yol: göreli yollar oturum klasörüne göre, satır ekleri atılarak; olmayan dosya nil.
    @Test func resolvesTerminalLinksAgainstTheSessionFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ao-kind-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Kaynak Klasör"), withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Kaynak Klasör/ş.swift")
        try Data("x".utf8).write(to: file)
        let expected = file.standardizedFileURL.path
        #expect(FileKind.resolve("Kaynak Klasör/ş.swift", relativeTo: dir.path)?.path == expected)
        #expect(FileKind.resolve("./Kaynak Klasör/ş.swift:12:4", relativeTo: dir.path)?.path == expected)
        #expect(FileKind.resolve(file.path + ":7", relativeTo: nil)?.path == expected)
        #expect(FileKind.resolve("Kaynak Klasör/yok.swift", relativeTo: dir.path) == nil)
        #expect(FileKind.resolve("ş.swift", relativeTo: nil) == nil)
    }
}
