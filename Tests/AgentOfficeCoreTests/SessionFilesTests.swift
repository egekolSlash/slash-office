import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct TerminalLinkTests {
    static func cells(_ text: String, styled: Range<Int>) -> [(character: Character, style: Int)] {
        text.enumerated().map { (character: $0.element, style: styled.contains($0.offset) ? 1 : 0) }
    }

    @Test func cleansPunctuationQuotesAndSuffixes() {
        #expect(TerminalLink.clean("`Sources/a.swift`") == "Sources/a.swift")
        #expect(TerminalLink.clean("(Sources/a.swift:12).") == "Sources/a.swift:12")
        #expect(TerminalLink.clean("AppModel.swift'te") == "AppModel.swift")
        #expect(TerminalLink.clean("“README.md’deki”") == "README.md")
        #expect(TerminalLink.clean("**a.swift**,") == "a.swift")
        #expect(TerminalLink.clean("__init__.py") == "__init__.py")
    }

    /// SwiftTerm yolun ardındaki kelimeleri ve alt satırı da verse bile tıklanan kelime önce denenir.
    @Test func prefersTheClickedWordOverSwiftTermsLongMatch() {
        let line = "Bak: Sources/AgentOffice/SessionList.swift dosyasında değişiklik var."
        let start = line.distance(from: line.startIndex, to: line.range(of: "Sources")!.lowerBound)
        let cells = Self.cells(line, styled: start..<(start + "Sources/AgentOffice/SessionList.swift".count))
        let link = "Sources/AgentOffice/SessionList.swift dosyasında değişiklik var. sonraki satır"
        let candidates = TerminalLink.candidates(cells: cells, column: start + 5, link: link)
        #expect(candidates.first == "Sources/AgentOffice/SessionList.swift")
    }

    /// Aynı renkteki kesintisiz metin: yola bitişik ek ve noktalama farklı renkteyse dışarıda kalır.
    @Test func styledRunStopsAtTheColourChange() {
        let line = "Bkz. a.swift'te"
        let cells = Self.cells(line, styled: 5..<12)
        let candidates = TerminalLink.candidates(cells: cells, column: 6, link: "a.swift'te")
        #expect(candidates.first == "a.swift")
    }

    @Test func resolvesPathsWithSpacesAndTrailingText() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ao-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Kaynak Klasör"), withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Kaynak Klasör/ş.swift")
        try Data("x".utf8).write(to: file)
        let line = "Kaynak Klasör/ş.swift'te iki hata var"
        let cells = Self.cells(line, styled: 0..<0)
        let candidates = TerminalLink.candidates(cells: cells, column: 15, link: line + " ve alt satır")
        let resolved = FileKind.resolve(firstOf: candidates, relativeTo: dir.path)
        #expect(resolved?.path == file.standardizedFileURL.path)
    }
}

@Suite struct TranscriptFilesTests {
    @Test func listsEditedReadAndMentionedFilesNewestFirst() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ao-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        for name in ["Sources/a.swift", "Sources/b.swift", "README.md"] {
            try Data("x".utf8).write(to: dir.appendingPathComponent(name))
        }
        let root = dir.standardizedFileURL.path
        let lines = [
            #"{"type":"user","message":{"content":"README.md'ye bak"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"\#(root)/Sources/a.swift"}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","content":"Sources/b.swift içeriği"}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"\#(root)/Sources/b.swift"}}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"`Sources/a.swift:12` ve https://x.com/a.html, yok.swift"}]}}"#,
        ]
        let files = TranscriptFiles.files(fromLines: lines.map { Substring($0) }, cwd: root)
        #expect(files == [
            SessionFile(path: root + "/Sources/a.swift", kind: .read),
            SessionFile(path: root + "/Sources/b.swift", kind: .edited),
            SessionFile(path: root + "/README.md", kind: .mentioned),
        ])
    }
}

@Suite struct ActivityHeatTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func countsBusyTimeInsideTheWindowOnly() {
        var log = ActivityLog()
        log.note(busy: true, at: start)
        log.note(busy: false, at: start.addingTimeInterval(600))
        log.note(busy: true, at: start.addingTimeInterval(3000))
        #expect(log.busySeconds(now: start.addingTimeInterval(3600)) == 1200)
        // 10 dakikalık ilk aralık pencereden çıktı, süren çalışma sayılmaya devam ediyor.
        #expect(log.busySeconds(now: start.addingTimeInterval(4800)) == 1800)
    }

    @Test func ranksSessionsBetweenTheLeastAndMostIdle() {
        var busy = ActivityLog(), some = ActivityLog(), idle = ActivityLog()
        busy.note(busy: true, at: start)
        busy.notePrompt(at: start)
        some.note(busy: true, at: start)
        some.note(busy: false, at: start.addingTimeInterval(300))
        let now = start.addingTimeInterval(600)
        let levels = ActivityHeat.levels(["busy": busy, "some": some, "idle": idle], now: now)
        #expect(levels["busy"] == 1)
        #expect(levels["idle"] == 0)
        #expect(levels["some"] == 0.35)
        #expect(ActivityHeat.levels(["a": idle, "b": ActivityLog()], now: now) == ["a": 0, "b": 0])
        #expect(ActivityHeat.levels(["a": busy], now: now) == ["a": 1])
    }

    @MainActor @Test func storeTracksWorkAndPrompts() {
        let store = AgentStore()
        store.register(id: "s", title: "s", cwd: "/tmp", state: .idle)
        store.apply([.promptSubmitted(text: "x")], to: "s", at: start)
        store.apply([.turnEnded], to: "s", at: start.addingTimeInterval(90))
        let activity = store.session("s")!.activity
        #expect(activity.busySeconds(now: start.addingTimeInterval(100)) == 90)
        #expect(activity.promptCount(now: start.addingTimeInterval(100)) == 1)
    }
}
