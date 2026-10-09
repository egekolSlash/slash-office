import Testing
@testable import AgentOfficeCore

@Suite struct ShortcutCatalogTests {
    @Test func idsAndKeysAreUnique() {
        let all = ShortcutCatalog.all
        #expect(Set(all.map(\.id)).count == all.count)
        let combos = all.map { "\($0.key)|\($0.modifiers.rawValue)" }
        #expect(Set(combos).count == combos.count)
    }

    /// Oturum ve panel gezinmesi her klavye düzeninde aynı: ⇧⌘ + ok tuşları.
    @Test func arrowShortcutsForSessionsAndPanes() {
        let expected: [(String, Shortcut.Key)] = [("session.previous", .up), ("session.next", .down),
                                                   ("pane.previous", .left), ("pane.next", .right)]
        for (id, key) in expected {
            let s = ShortcutCatalog.shortcut(id)
            #expect(s.key == key)
            #expect(s.modifiers == [.command, .shift])
        }
    }

    /// Düzene göre yeri değişen noktalama kısayolları kalmadı (Türkçe Q'da [ ] ; ' anlamsız yerlerde).
    @Test func noLayoutDependentPunctuationLeft() {
        for s in ShortcutCatalog.all {
            if case .character(let c) = s.key { #expect(!"[];'".contains(c), "\(s.id)") }
        }
    }

    @Test func symbolsRenderModifiersInAppleOrder() {
        #expect(ShortcutCatalog.shortcut("session.previous").symbols == "⇧⌘↑")
        #expect(ShortcutCatalog.shortcut("session.resumeAll").symbols == "⇧⌘R")
        #expect(ShortcutCatalog.shortcut("text.bigger").symbols == "⌘+")
        #expect(ShortcutCatalog.shortcut("session.removeStopped").symbols == "⇧⌘⌫")
        #expect(ShortcutCatalog.shortcut("agents.customize").symbols == "⇧⌘A")
    }

    @Test func everyMenuCommandHasAShortcut() {
        let ids = ["session.newClaude", "pane.new", "pane.newBeside", "mode.office", "mode.work", "mode.focus",
                   "text.bigger", "text.smaller", "text.actual", "session.jumpToWaiting", "session.previous",
                   "session.next", "pane.previous", "pane.next", "session.resume", "session.removeStopped",
                   "session.resumeAll", "pane.close", "agents.customize"]
        #expect(Set(ShortcutCatalog.all.map(\.id)) == Set(ids))
    }

    /// ⌘= de yazıyı büyütür: Caps Lock açıkken de, `=` Shift istiyorsa (Türkçe Q'da ⇧0) Shift'le de.
    @Test func biggerTextAcceptsCommandEquals() {
        let capsLock: UInt = 1 << 16, shift: UInt = 1 << 17, control: UInt = 1 << 18, option: UInt = 1 << 19
        let command: UInt = 1 << 20
        #expect(Shortcut.Modifiers(eventFlags: command | capsLock) == .command)
        #expect(Shortcut.Modifiers(eventFlags: command | shift | option | control) == [.command, .shift, .option, .control])
        #expect(ShortcutCatalog.isBiggerTextEquals(characters: "=", modifiers: .command))
        #expect(ShortcutCatalog.isBiggerTextEquals(characters: "=", modifiers: [.command, .shift]))
        #expect(!ShortcutCatalog.isBiggerTextEquals(characters: "=", modifiers: [.command, .option]))
        #expect(!ShortcutCatalog.isBiggerTextEquals(characters: "=", modifiers: []))
        #expect(!ShortcutCatalog.isBiggerTextEquals(characters: "-", modifiers: .command))
    }

    /// Rehber yazıyı büyütmeyi düzende ⌘='nin basılışıyla gösterir (Türkçe Q'da "+" ⇧4 ister ve ⌘⇧4 ekran görüntüsüdür).
    @Test func biggerTextDisplayUsesEqualsOnThisLayout() {
        #expect(ShortcutCatalog.biggerTextDisplay(equalsTyping: ([], "=")) == "⌘=")
        #expect(ShortcutCatalog.biggerTextDisplay(equalsTyping: (.shift, "0")) == "⇧⌘0")
        #expect(ShortcutCatalog.biggerTextDisplay(equalsTyping: nil) == "⌘+")
    }
}

