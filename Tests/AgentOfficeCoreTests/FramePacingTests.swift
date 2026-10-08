import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct FramePacingTests {
    @Test func paces() {
        #expect(FramePacing.mode(moving: true, interacting: false, animating: true, visible: true, mini: false) == .native)
        #expect(FramePacing.mode(moving: false, interacting: true, animating: false, visible: true, mini: false) == .native)
        #expect(FramePacing.mode(moving: false, interacting: false, animating: true, visible: true, mini: false) == .fixed(12))
        #expect(FramePacing.mode(moving: true, interacting: false, animating: true, visible: true, mini: true) == .fixed(12))
        // Mini ofiste de jest (kaydırma, yakınlaştırma) akıcı olsun.
        #expect(FramePacing.mode(moving: false, interacting: true, animating: true, visible: true, mini: true) == .native)
        // Yerinde tek seferlik hareket ya da geçiş (yürüme yok): 30 fps; mini ofiste 12.
        #expect(FramePacing.mode(moving: false, acting: true, interacting: false, animating: true, visible: true, mini: false) == .fixed(30))
        #expect(FramePacing.mode(moving: true, acting: true, interacting: false, animating: true, visible: true, mini: false) == .native)
        #expect(FramePacing.mode(moving: false, acting: true, interacting: false, animating: true, visible: true, mini: true) == .fixed(12))
        #expect(FramePacing.mode(moving: true, interacting: true, animating: true, visible: false, mini: false) == .paused)
        // Köylü yok, hareket yok: son kare ekranda kalır, çizim durur.
        #expect(FramePacing.mode(moving: false, interacting: false, animating: false, visible: true, mini: false) == .paused)
        #expect(FramePacing.mode(moving: false, interacting: false, animating: false, visible: true, mini: true) == .paused)
    }
}

/// Enerji tasarrufu kapalıyken görünür ve canlı ofis her zaman ekran hızında (mini dahil); gizliyken yine durur.
@Suite struct FramePacingSavingTests {
    @Test(arguments: [false, true]) func withoutSavingEverythingVisibleIsNative(mini: Bool) {
        #expect(FramePacing.mode(moving: false, interacting: false, animating: true, visible: true, mini: mini, saving: false) == .native)
        #expect(FramePacing.mode(moving: false, acting: true, interacting: false, animating: true, visible: true, mini: mini, saving: false) == .native)
        #expect(FramePacing.mode(moving: true, interacting: false, animating: true, visible: true, mini: mini, saving: false) == .native)
    }

    @Test(arguments: [false, true]) func hiddenPausesEvenWithoutSaving(mini: Bool) {
        #expect(FramePacing.mode(moving: true, acting: true, interacting: true, animating: true, visible: false, mini: mini, saving: false) == .paused)
    }

    @Test func nothingToAnimatePausesEvenWithoutSaving() {
        #expect(FramePacing.mode(moving: false, interacting: false, animating: false, visible: true, mini: false, saving: false) == .paused)
        #expect(FramePacing.mode(moving: false, interacting: false, animating: false, visible: true, mini: true, saving: false) == .paused)
    }

    @Test func savingKeepsTodaysRules() {
        #expect(FramePacing.mode(moving: false, acting: true, interacting: false, animating: true, visible: true, mini: false, saving: true) == .fixed(30))
        #expect(FramePacing.mode(moving: false, interacting: false, animating: true, visible: true, mini: true, saving: true) == .fixed(12))
    }
}

@Suite struct OfficeArtLocationTests {
    @Test func prefersBundleThenRepoThenNil() {
        let bundle = URL(fileURLWithPath: "/App.app/Contents/Resources")
        let repo = URL(fileURLWithPath: "/repo")
        let both: Set = ["/App.app/Contents/Resources/OfficeArt/office-art.json", "/repo/Resources/OfficeArt/office-art.json"]
        #expect(OfficeArtLocation.find(bundleResources: bundle, repoRoot: repo, fileExists: both.contains)?.path == "/App.app/Contents/Resources/OfficeArt")
        let repoOnly: Set = ["/repo/Resources/OfficeArt/office-art.json"]
        #expect(OfficeArtLocation.find(bundleResources: bundle, repoRoot: repo, fileExists: repoOnly.contains)?.path == "/repo/Resources/OfficeArt")
        #expect(OfficeArtLocation.find(bundleResources: nil, repoRoot: repo, fileExists: { _ in false }) == nil)
    }
}
