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

@Suite struct OfficeCameraMappingTests {
    @Test(arguments: [(0.3, -1.1, 37.0), (4.0, 2.0, 120.0)])
    func orthographicCameraMatchesViewportProjection(cx: Double, cy: Double, zoom: Double) {
        let viewport = OfficeViewport(centerX: cx, centerY: cy, zoom: zoom)
        let size = (width: 900.0, height: 600.0)
        let t = viewport.cameraTarget()
        #expect(abs(t.y) < 1e-9)
        let scale = viewport.orthographicScale(viewHeight: size.height)
        // Ortografik kamera: sağ = (1,0,-1)/√2, yukarı = (-1,2,-1)/√6, nokta başına birim = 2·scale / yükseklik.
        for p in [(1.0, 0.0, 2.0), (3.5, 1.2, -0.5), (-2.0, 0.4, 5.0)] {
            let d = (p.0 - t.x, p.1 - t.y, p.2 - t.z)
            let right = (d.0 - d.2) / 2.0.squareRoot()
            let up = (-d.0 + 2 * d.1 - d.2) / 6.0.squareRoot()
            let ppu = size.height / (2 * scale)
            let expected = viewport.project(x: p.0, y: p.1, z: p.2, viewSize: size)
            #expect(abs(size.width / 2 + right * ppu - expected.x) < 1e-6)
            #expect(abs(size.height / 2 - up * ppu - expected.y) < 1e-6)
        }
    }
}
