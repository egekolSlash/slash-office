import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct TerminalRedrawTests {
    @Test func energySavingOnlyTheFocusedTerminalOfTheActiveAppDrawsImmediately() {
        #expect(TerminalRedraw.interval(focused: true, appActive: true, energySaving: true) == nil)
        #expect(TerminalRedraw.interval(focused: false, appActive: true, energySaving: true) == TerminalRedraw.unfocusedInterval)
        #expect(TerminalRedraw.interval(focused: true, appActive: false, energySaving: true) == TerminalRedraw.backgroundInterval)
        #expect(TerminalRedraw.interval(focused: false, appActive: false, energySaving: true) == TerminalRedraw.backgroundInterval)
    }

    @Test func withoutEnergySavingEveryTerminalOfTheActiveAppDrawsImmediately() {
        #expect(TerminalRedraw.interval(focused: false, appActive: true, energySaving: false) == nil)
        #expect(TerminalRedraw.interval(focused: true, appActive: true, energySaving: false) == nil)
        #expect(TerminalRedraw.interval(focused: false, appActive: false, energySaving: false) == TerminalRedraw.backgroundInterval)
    }

    @Test func scrolledTerminalAlwaysDrawsImmediately() {
        #expect(TerminalRedraw.interval(focused: false, appActive: true, energySaving: true, scrolling: true) == nil)
        #expect(TerminalRedraw.interval(focused: false, appActive: false, energySaving: true, scrolling: true) == nil)
    }

    @Test func scrollingLastsAShortGrace() {
        let now = Date()
        #expect(TerminalRedraw.isScrolling(lastScroll: now.addingTimeInterval(-0.2), now: now))
        #expect(!TerminalRedraw.isScrolling(lastScroll: now.addingTimeInterval(-TerminalRedraw.scrollGrace - 0.01), now: now))
        #expect(!TerminalRedraw.isScrolling(lastScroll: nil, now: now))
    }
}
