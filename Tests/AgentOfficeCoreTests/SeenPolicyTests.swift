import Foundation
import Testing
@testable import AgentOfficeCore

/// Bir iş, kullanıcı gerçekten baktığını bir hareketle (fare, tıklama, tuş) gösterene kadar "görülmedi" kalır.
@Suite struct SeenPolicyTests {
    @Test func finishIsNeverWatched() {
        #expect(SeenPolicy.finishIsWatched == false)
    }

    @Test func activityMarksFocusedUnseenSessionSeen() {
        #expect(SeenPolicy.marksSeen(appActive: true, officeMode: false, focusedVisible: true, unseen: true))
        #expect(!SeenPolicy.marksSeen(appActive: true, officeMode: false, focusedVisible: true, unseen: false))
        #expect(!SeenPolicy.marksSeen(appActive: true, officeMode: false, focusedVisible: false, unseen: true))
    }

    @Test func noActivityEffectInOfficeModeOrInactiveApp() {
        #expect(!SeenPolicy.marksSeen(appActive: false, officeMode: false, focusedVisible: true, unseen: true))
        #expect(!SeenPolicy.marksSeen(appActive: true, officeMode: true, focusedVisible: true, unseen: true))
    }

    /// Kullanıcı aynı panelde çalışırken iş biter: bitişte görülmedi olur, ilk hareketle görüldü.
    @MainActor @Test func typingInTheFocusedPaneMarksSeen() {
        let store = AgentStore()
        store.register(id: "a", title: "a", cwd: "/p")
        store.apply([.promptSubmitted(text: "go")], to: "a")
        store.apply([.turnEnded], to: "a", watched: SeenPolicy.finishIsWatched)
        #expect(store.session("a")?.unseenFinish == true)
        if SeenPolicy.marksSeen(appActive: true, officeMode: false, focusedVisible: true,
                                unseen: store.session("a")?.unseenFinish == true) {
            store.markSeen("a")
        }
        #expect(store.session("a")?.unseenFinish == false)
    }
}
