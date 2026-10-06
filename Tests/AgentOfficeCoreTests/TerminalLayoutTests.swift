import Testing
@testable import AgentOfficeCore

@Suite struct TerminalLayoutTests {
    @Test func showReplacesFocusedPane() {
        var layout = TerminalLayout()
        layout.show("a")
        #expect(layout.visible == ["a"] && layout.focused == "a")
        layout.add("b")
        #expect(layout.visible == ["a", "b"] && layout.focused == "b")
        layout.show("c")
        #expect(layout.visible == ["a", "c"] && layout.focused == "c")
        layout.show("a")
        #expect(layout.visible == ["a", "c"] && layout.focused == "a")
    }

    @Test func addCapsAtFourDroppingOldestUnfocused() {
        var layout = TerminalLayout()
        for id in ["a", "b", "c", "d"] { layout.add(id) }
        layout.show("a")
        layout.add("e")
        #expect(layout.visible == ["a", "c", "d", "e"])
        #expect(layout.focused == "e")
    }

    @Test func closeMovesFocusToNeighbourAndEmptiesCleanly() {
        var layout = TerminalLayout()
        for id in ["a", "b", "c"] { layout.add(id) }
        layout.close("c")
        #expect(layout.visible == ["a", "b"] && layout.focused == "b")
        layout.close("a")
        #expect(layout.visible == ["b"] && layout.focused == "b")
        layout.close("b")
        #expect(layout.visible.isEmpty && layout.focused == nil)
        layout.close("zzz")
        #expect(layout.visible.isEmpty && layout.focused == nil)
    }

    @Test func replaceKeepsSlotAndFocuses() {
        var layout = TerminalLayout()
        layout.add("a")
        layout.add("launcher-1")
        layout.add("c")
        layout.replace("launcher-1", with: "b")
        #expect(layout.visible == ["a", "b", "c"])
        #expect(layout.focused == "b")
        // Zaten görünen bir oturuma dönüşürse boş panel kapanır.
        layout.add("launcher-2")
        layout.replace("launcher-2", with: "a")
        #expect(layout.visible == ["a", "b", "c"])
        #expect(layout.focused == "a")
        #expect(TerminalLayout.isLauncher("launcher-2") && !TerminalLayout.isLauncher("a"))
    }

    @Test func cycleWraps() {
        var layout = TerminalLayout()
        for id in ["a", "b", "c"] { layout.add(id) }
        layout.cycle()
        #expect(layout.focused == "a")
        layout.cycle()
        #expect(layout.focused == "b")
        var single = TerminalLayout()
        single.cycle()
        #expect(single.focused == nil)
    }

    @Test func gridShape() {
        var layout = TerminalLayout()
        #expect((layout.columns, layout.rows) == (1, 1))
        layout.add("a")
        #expect((layout.columns, layout.rows) == (1, 1))
        layout.add("b")
        #expect((layout.columns, layout.rows) == (2, 1))
        layout.add("c")
        #expect((layout.columns, layout.rows) == (2, 2))
        layout.add("d")
        #expect((layout.columns, layout.rows) == (2, 2))
    }

    @Test func cycleBackwardWraps() {
        var layout = TerminalLayout()
        layout.add("a"); layout.add("b"); layout.add("c")
        layout.cycle(backward: true)
        #expect(layout.focused == "b")
        layout.show("a")
        layout.cycle(backward: true)
        #expect(layout.focused == "c")
    }
}
