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

    /// Eklemeler eski ızgarayı verir: 2 yan yana, 3–4 2×2 (yeni panel en büyük panelin uzun kenarından bölünür).
    @Test func addBuildsTheOldGrid() {
        var layout = TerminalLayout()
        #expect(layout.root == nil)
        layout.add("a")
        #expect(layout.root == .leaf("a"))
        layout.add("b")
        #expect(layout.root == .split(.horizontal, .leaf("a"), .leaf("b")))
        layout.add("c")
        layout.add("d")
        #expect(layout.root == .split(.horizontal, .split(.vertical, .leaf("a"), .leaf("c")),
                                      .split(.vertical, .leaf("b"), .leaf("d"))))
    }

    @Test func edgeZones() {
        #expect(TerminalLayout.edge(x: 10, y: 300, width: 800, height: 600) == .left)
        #expect(TerminalLayout.edge(x: 790, y: 300, width: 800, height: 600) == .right)
        #expect(TerminalLayout.edge(x: 400, y: 20, width: 800, height: 600) == .top)
        #expect(TerminalLayout.edge(x: 400, y: 590, width: 800, height: 600) == .bottom)
        #expect(TerminalLayout.edge(x: 400, y: 300, width: 800, height: 600) == .center)
        // Köşede daha yakın kenar kazanır.
        #expect(TerminalLayout.edge(x: 30, y: 10, width: 800, height: 600) == .top)
    }

    /// Listeden sürüklenen oturum bırakılan kenara yerleşir; ortaya bırakılırsa o paneli değiştirir.
    @Test func droppingANewSessionSplitsTheTargetOnThatEdge() {
        var layout = TerminalLayout()
        layout.add("a")
        layout.drop("b", on: "a", edge: .bottom)
        #expect(layout.root == .split(.vertical, .leaf("a"), .leaf("b")))
        #expect(layout.focused == "b")
        layout.drop("c", on: "b", edge: .left)
        #expect(layout.root == .split(.vertical, .leaf("a"), .split(.horizontal, .leaf("c"), .leaf("b"))))
        layout.drop("d", on: "a", edge: .center)
        #expect(layout.root == .split(.vertical, .leaf("d"), .split(.horizontal, .leaf("c"), .leaf("b"))))
        #expect(Set(layout.visible) == ["b", "c", "d"] && layout.focused == "d")
    }

    /// Panelin kendisi sürüklenince yerinden kalkıp yeni yerine geçer; ortaya bırakılırsa iki panel yer değiştirir.
    @Test func draggingAPaneMovesOrSwapsIt() {
        var layout = TerminalLayout()
        for id in ["a", "b", "c"] { layout.add(id) }
        // (a/c | b): c'yi b'nin altına taşı.
        layout.drop("c", on: "b", edge: .bottom)
        #expect(layout.root == .split(.horizontal, .leaf("a"), .split(.vertical, .leaf("b"), .leaf("c"))))
        layout.drop("a", on: "c", edge: .center)
        #expect(layout.root == .split(.horizontal, .leaf("c"), .split(.vertical, .leaf("b"), .leaf("a"))))
        #expect(layout.focused == "a")
        // Kendi üstüne bırakmak bir şey değiştirmez.
        let before = layout.root
        layout.drop("b", on: "b", edge: .left)
        #expect(layout.root == before)
    }

    /// Alan doluyken yeni oturum kenara bırakılamaz, bırakıldığı paneli değiştirir; var olan paneller taşınabilir.
    @Test func fullLayoutOnlyReplacesButStillMoves() {
        var layout = TerminalLayout()
        for id in ["a", "b", "c", "d"] { layout.add(id) }
        #expect(layout.dropEdge(for: "e", on: "a", edge: .left) == .center)
        #expect(layout.dropEdge(for: "b", on: "a", edge: .left) == .left)
        layout.drop("e", on: "a", edge: .left)
        #expect(Set(layout.visible) == ["e", "b", "c", "d"])
        layout.drop("b", on: "e", edge: .top)
        #expect(layout.visible.count == 4)
        #expect(layout.root == .split(.horizontal, .split(.vertical, .split(.vertical, .leaf("b"), .leaf("e")), .leaf("c")),
                                      .leaf("d")))
    }

    @Test func closeCollapsesTheSplit() {
        var layout = TerminalLayout()
        for id in ["a", "b", "c"] { layout.add(id) }
        layout.close("a")
        #expect(layout.root == .split(.horizontal, .leaf("c"), .leaf("b")))
        layout.close("b")
        #expect(layout.root == .leaf("c"))
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

    @Test func adjacentSkipsSessionsOpenInOtherPanes() {
        var layout = TerminalLayout()
        layout.add("b"); layout.add("d")   // b ve d açık, odak d'de
        let ids = ["a", "b", "c", "d", "e"]
        // Odaktaki panel (d) değişir; başka panelde açık olan b atlanır.
        #expect(layout.adjacent(in: ids, offset: 1) == "e")
        #expect(layout.adjacent(in: ids, offset: -1) == "c")
        layout.show("a")                    // d'nin yerine a; odak a
        #expect(layout.adjacent(in: ids, offset: 1) == "c")   // b atlanır
        #expect(layout.adjacent(in: ids, offset: -1) == "e")  // başa sarar
    }

    @Test func adjacentWithNothingElseToShow() {
        var layout = TerminalLayout()
        layout.add("a"); layout.add("b")
        #expect(layout.adjacent(in: ["a", "b"], offset: 1) == nil)
        #expect(TerminalLayout().adjacent(in: ["x", "y"], offset: 1) == "x")
    }
}
