import Testing
@testable import AgentOfficeCore

@Suite struct DiffParserTests {
    @Test func modifiedFileWithTwoHunks() {
        let patch = """
        diff --git a/Sources/main.swift b/Sources/main.swift
        index 1111111..2222222 100644
        --- a/Sources/main.swift
        +++ b/Sources/main.swift
        @@ -1,3 +1,3 @@
         import Foundation
        -let a = 1
        +let a = 2
         print(a)
        @@ -10,2 +10,3 @@ func f() {
         let x = 0
        +let y = 1
         return
        """
        let files = DiffParser.parse(patch)
        #expect(files.count == 1)
        let file = files[0]
        #expect(file.path == "Sources/main.swift")
        #expect(file.change == .modified)
        #expect(file.hunks.count == 2)
        #expect(file.hunks[1].header == "@@ -10,2 +10,3 @@ func f() {")
        #expect(file.additions == 2 && file.deletions == 1)
        #expect(file.hunks[0].lines.map(\.kind) == [.context, .removed, .added, .context])
        #expect(file.hunks[0].lines[1].text == "let a = 1")
    }

    @Test func addedDeletedAndRenamed() {
        let patch = """
        diff --git a/new.txt b/new.txt
        new file mode 100644
        index 0000000..e69de29
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1 @@
        +hello
        diff --git a/old.txt b/old.txt
        deleted file mode 100644
        index e69de29..0000000
        --- a/old.txt
        +++ /dev/null
        @@ -1 +0,0 @@
        -bye
        diff --git a/a.txt b/b.txt
        similarity index 100%
        rename from a.txt
        rename to b.txt
        """
        let files = DiffParser.parse(patch)
        #expect(files.map(\.path) == ["new.txt", "old.txt", "b.txt"])
        #expect(files[0].change == .added && files[0].additions == 1)
        #expect(files[1].change == .deleted && files[1].deletions == 1)
        #expect(files[2].change == .renamed(from: "a.txt") && files[2].hunks.isEmpty)
    }

    @Test func binaryFile() {
        let patch = """
        diff --git a/img/logo.png b/img/logo.png
        index 1111111..2222222 100644
        Binary files a/img/logo.png and b/img/logo.png differ
        """
        let files = DiffParser.parse(patch)
        #expect(files.count == 1 && files[0].isBinary && files[0].hunks.isEmpty && files[0].path == "img/logo.png")
    }

    @Test func pathsWithSpacesTurkishAndQuoting() {
        let plain = """
        diff --git a/Klasör Adı/ş.txt b/Klasör Adı/ş.txt
        new file mode 100644
        --- /dev/null
        +++ b/Klasör Adı/ş.txt
        @@ -0,0 +1 @@
        +x
        """
        #expect(DiffParser.parse(plain).first?.path == "Klasör Adı/ş.txt")
        // core.quotePath açıkken git yolu tırnaklı ve octal kaçışlı yazar.
        let quoted = """
        diff --git "a/Klas\\303\\266r/\\305\\237.txt" "b/Klas\\303\\266r/\\305\\237.txt"
        index 1..2 100644
        Binary files "a/Klas\\303\\266r/\\305\\237.txt" and "b/Klas\\303\\266r/\\305\\237.txt" differ
        """
        #expect(DiffParser.parse(quoted).first?.path == "Klasör/ş.txt")
    }

    @Test func noNewlineMarkerIsNotALine() {
        let patch = """
        diff --git a/a b/a
        --- a/a
        +++ b/a
        @@ -1 +1 @@
        -x
        \\ No newline at end of file
        +y
        \\ No newline at end of file
        """
        let file = DiffParser.parse(patch)[0]
        #expect(file.hunks[0].lines.count == 2 && file.additions == 1 && file.deletions == 1)
    }

    @Test func emptyInput() {
        #expect(DiffParser.parse("").isEmpty)
    }
}
