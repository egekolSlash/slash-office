import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct FramePacingTests {
    @Test func paces() {
        #expect(FramePacing.mode(moving: true, interacting: false, animating: true, visible: true, mini: false) == .native)
        #expect(FramePacing.mode(moving: false, interacting: true, animating: false, visible: true, mini: false) == .native)
        #expect(FramePacing.mode(moving: false, interacting: false, animating: true, visible: true, mini: false) == .fixed(12))
        #expect(FramePacing.mode(moving: true, interacting: false, animating: true, visible: true, mini: true) == .fixed(12))
        #expect(FramePacing.mode(moving: true, interacting: true, animating: true, visible: false, mini: false) == .paused)
        // Köylü yok, hareket yok: son kare ekranda kalır, çizim durur.
        #expect(FramePacing.mode(moving: false, interacting: false, animating: false, visible: true, mini: false) == .paused)
        #expect(FramePacing.mode(moving: false, interacting: false, animating: false, visible: true, mini: true) == .paused)
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
