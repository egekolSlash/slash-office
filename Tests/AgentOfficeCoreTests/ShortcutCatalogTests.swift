import Testing
@testable import AgentOfficeCore

@Suite struct ShortcutCatalogTests {
    @Test func idsAndKeysAreUnique() {
        let all = ShortcutCatalog.all
        #expect(Set(all.map(\.id)).count == all.count)
        let combos = all.map { "\($0.key)|\($0.modifiers.rawValue)" }
        #expect(Set(combos).count == combos.count)
    }

    /// Oturum ve panel gezinmesi her klavye düzeninde aynı: ⌘⌥ + ok tuşları.
    @Test func arrowShortcutsForSessionsAndPanes() {
        let expected: [(String, Shortcut.Key)] = [("session.previous", .left), ("session.next", .right),
                                                   ("pane.previous", .up), ("pane.next", .down)]
        for (id, key) in expected {
            let s = ShortcutCatalog.shortcut(id)
            #expect(s.key == key)
            #expect(s.modifiers == [.command, .option])
        }
    }

    /// Düzene göre yeri değişen noktalama kısayolları kalmadı (Türkçe Q'da [ ] ; ' anlamsız yerlerde).
    @Test func noLayoutDependentPunctuationLeft() {
        for s in ShortcutCatalog.all {
            if case .character(let c) = s.key { #expect(!"[];'".contains(c), "\(s.id)") }
        }
    }

    @Test func symbolsRenderModifiersInAppleOrder() {
        #expect(ShortcutCatalog.shortcut("session.previous").symbols == "⌥⌘←")
        #expect(ShortcutCatalog.shortcut("session.resumeAll").symbols == "⇧⌘R")
        #expect(ShortcutCatalog.shortcut("text.bigger").symbols == "⌘+")
        #expect(ShortcutCatalog.shortcut("session.removeStopped").symbols == "⇧⌘⌫")
    }

    @Test func everyMenuCommandHasAShortcut() {
        let ids = ["session.newClaude", "pane.new", "pane.newBeside", "mode.office", "mode.work", "mode.focus",
                   "text.bigger", "text.smaller", "text.actual", "session.jumpToWaiting", "session.previous",
                   "session.next", "pane.previous", "pane.next", "session.resume", "session.removeStopped",
                   "session.resumeAll", "pane.close"]
        #expect(Set(ShortcutCatalog.all.map(\.id)) == Set(ids))
    }
}
