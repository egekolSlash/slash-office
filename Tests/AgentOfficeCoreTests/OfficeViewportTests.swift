import Foundation
import Testing
import simd
@testable import AgentOfficeCore

@Suite struct OfficeViewportTests {
    let size = (width: 900.0, height: 600.0)

    func viewport(zoom: Double = 60) -> OfficeViewport {
        OfficeViewport(targetX: 3, targetZ: 4, zoom: zoom, fitZoom: 60, planMinZ: 0)
    }

    @Test func targetProjectsToCenterAndZoomIsPixelsPerMeter() {
        let v = viewport()
        let c = v.project(x: 3, y: 0, z: 4, viewSize: size)
        #expect(abs(c.x - 450) < 1e-6 && abs(c.y - 300) < 1e-6)
        // Hedefte, ekran düzlemine paralel küçük bir adım `zoom` nokta tutar.
        let right = v.project(x: 3.01, y: 0, z: 4, viewSize: size)
        #expect(abs((right.x - c.x) / 0.01 - 60) < 0.1)
        // Öndeki (büyük z) nokta ekranda aşağıda, yukarıdaki nokta yukarıda.
        #expect(v.project(x: 3, y: 0, z: 5, viewSize: size).y > c.y)
        #expect(v.project(x: 3, y: 1, z: 4, viewSize: size).y < c.y)
        // Perspektif: öndeki 1 m arkadakinden geniş görünür.
        let frontWidth = v.project(x: 4, y: 0, z: 6, viewSize: size).x - v.project(x: 3, y: 0, z: 6, viewSize: size).x
        let backWidth = v.project(x: 4, y: 0, z: 1, viewSize: size).x - v.project(x: 3, y: 0, z: 1, viewSize: size).x
        #expect(frontWidth > backWidth)
    }

    @Test func pitchAndBendFollowNearness() {
        let far = viewport(zoom: 60), near = viewport(zoom: OfficeViewport.maxZoom)
        #expect(far.nearness == 0 && near.nearness == 1)
        #expect(abs(far.pitchDegrees - 40) < 1e-9 && abs(near.pitchDegrees - 31) < 1e-9)
        #expect(abs(far.bend.k - 0.012) < 1e-9 && abs(near.bend.k - 0.05) < 1e-9)
        #expect(abs(far.bend.startZ - (0 - 1)) < 1e-9)       // uzakta planın arkasından
        #expect(abs(near.bend.startZ - (4 - 2.5)) < 1e-9)    // yakında hedefin 2,5 m arkasından
    }

    @Test func bendLowersOnlyPointsBehindStart() {
        let v = viewport(zoom: OfficeViewport.maxZoom)       // bükülme z = 1,5'ten başlar
        let k = v.bend.k
        // Başlangıcın önündeki nokta bükülmez: aynı noktanın bükülmesiz izdüşümüyle aynı.
        let front = v.project(x: 3, y: 0, z: 2, viewSize: size)
        let frontFlat = v.projectUnbent(x: 3, y: 0, z: 2, viewSize: size)
        #expect(abs(front.y - frontFlat.y) < 1e-9)
        // Arkasındaki nokta k·d² kadar alçalmış gibi izdüşer.
        let behind = v.project(x: 3, y: 0, z: -2, viewSize: size)
        let lowered = v.projectUnbent(x: 3, y: -k * 3.5 * 3.5, z: -2, viewSize: size)
        #expect(abs(behind.y - lowered.y) < 1e-9 && abs(behind.x - lowered.x) < 1e-9)
    }

    @Test(arguments: [0.0, 0.5, 1.2])
    func pointInvertsProjectInFlatArea(height: Double) {
        let v = viewport(zoom: 90)
        let p = v.project(x: 4.2, y: height, z: 5.1, viewSize: size)
        let back = v.point(atX: p.x, y: p.y, height: height, viewSize: size)
        #expect(abs(back.x - 4.2) < 1e-6 && abs(back.z - 5.1) < 1e-6)
    }

    @Test(arguments: [60.0, 150.0])
    func viewProjectionMatchesProjectUnbent(zoom: Double) {
        let v = viewport(zoom: zoom)
        let m = v.viewProjection(viewSize: size)
        for p in [SIMD3(1.0, 0.0, 2.0), SIMD3(5.5, 1.2, 6.0), SIMD3(2.0, 0.4, 3.0), SIMD3(-8.0, 3.0, -12.0)] {
            let c = m * SIMD4<Float>(Float(p.x), Float(p.y), Float(p.z), 1)
            let x = (Double(c.x / c.w) + 1) / 2 * size.width, y = (1 - Double(c.y / c.w)) / 2 * size.height
            let e = v.projectUnbent(x: p.x, y: p.y, z: p.z, viewSize: size)
            #expect(abs(x - e.x) < 0.05 && abs(y - e.y) < 0.05, "\(p)")
            #expect(c.z / c.w > 0 && c.z / c.w < 1)
        }
        // Kameraya yakın nokta daha küçük derinlik alır.
        let near = m * SIMD4<Float>(3, 0, 6, 1), far = m * SIMD4<Float>(3, 0, 0, 1)
        #expect(near.z / near.w < far.z / far.w)
    }

    @Test func panMovesGroundWithFingerAndIsClamped() {
        var v = viewport()
        let bounds = PlanRect(minX: 0, minZ: 0, maxX: 8, maxZ: 8)
        let before = v.project(x: 3, y: 0, z: 4, viewSize: size)
        v.pan(dx: 30, dy: -20, within: bounds)
        let after = v.project(x: 3, y: 0, z: 4, viewSize: size)
        #expect(abs(after.x - before.x - 30) < 0.5 && abs(after.y - before.y + 20) < 0.5)
        v.pan(dx: -100_000, dy: 100_000, within: bounds)
        #expect(v.targetX <= 8 + 3 && v.targetX >= 0 - 3 && v.targetZ >= 0 - 3 && v.targetZ <= 8 + 3)
    }

    @Test func zoomKeepsAnchorGroundPointFixed() {
        var v = viewport()
        let bounds = PlanRect(minX: -20, minZ: -20, maxX: 20, maxZ: 20)
        let ground = v.point(atX: 620, y: 380, height: 0, viewSize: size)
        v.zoom(by: 1.8, anchorX: 620, anchorY: 380, viewSize: size, limits: 20...260, within: bounds)
        #expect(abs(v.zoom - 108) < 1e-9)
        let again = v.project(x: ground.x, y: 0, z: ground.z, viewSize: size)
        #expect(abs(again.x - 620) < 1 && abs(again.y - 380) < 1, "\(again)")
        v.zoom(by: 100, anchorX: 0, anchorY: 0, viewSize: size, limits: 20...260, within: bounds)
        #expect(v.zoom == 260)
    }

    @Test(arguments: [(900.0, 600.0), (420.0, 280.0), (320.0, 900.0), (2400.0, 1400.0)])
    func fittingKeepsCornersInside(width: Double, height: Double) {
        let rect = PlanRect(minX: -2, minZ: 0, maxX: 9, maxZ: 12)
        let view = (width: width, height: height)
        let v = OfficeViewport.fitting(rect, height: 1.6, viewSize: view)
        #expect(v.fitZoom == v.zoom && v.nearness == 0)
        guard v.zoom > OfficeViewport.minFitZoom else { return }
        for x in [rect.minX, rect.maxX] { for z in [rect.minZ, rect.maxZ] { for y in [0.0, 1.6] {
            let p = v.project(x: x, y: y, z: z, viewSize: view)
            #expect(p.x >= -0.5 && p.x <= width + 0.5 && p.y >= -0.5 && p.y <= height + 0.5, "\(x),\(y),\(z) → \(p)")
        } } }
    }

    @Test func fittingFallsBackToFrontWhenTooBig() {
        let rect = PlanRect(minX: -30, minZ: 0, maxX: 30, maxZ: 60)
        let view = (width: 420.0, height: 280.0)
        let v = OfficeViewport.fitting(rect, height: 1.6, viewSize: view)
        #expect(v.zoom == OfficeViewport.minFitZoom)
        let front = v.project(x: (rect.minX + rect.maxX) / 2, y: 0, z: rect.maxZ, viewSize: view)
        #expect(front.y <= view.height && front.y > view.height - 60)
    }

    @Test func fittingEmptyAndTiny() {
        let empty = OfficeViewport.fitting(.zero, height: 1.6, viewSize: (800, 600))
        #expect(empty.zoom.isFinite && empty.zoom > 0 && empty.targetX.isFinite && empty.targetZ.isFinite)
        let limits = OfficeViewport.zoomLimits(fit: empty)
        #expect(limits.lowerBound > 0 && limits.upperBound >= limits.lowerBound)
        let zero = OfficeViewport.fitting(.zero, height: 1.6, viewSize: (0, 0))
        #expect(zero.zoom.isFinite && zero.zoom > 0)
        let tiny = OfficeViewport.fitting(PlanRect(minX: 0, minZ: 0, maxX: 0.5, maxZ: 0.5), height: 1.6, viewSize: (2000, 1400))
        #expect(tiny.zoom <= OfficeViewport.maxFitZoom)
    }

    @Test func focusingCentersThePoint() {
        let fit = OfficeViewport.fitting(PlanRect(minX: 0, minZ: 0, maxX: 10, maxZ: 10), height: 1.6, viewSize: size)
        let v = OfficeViewport.focusing(x: 2, z: 7, zoom: 150, fit: fit)
        let p = v.project(x: 2, y: 0, z: 7, viewSize: size)
        #expect(abs(p.x - 450) < 1e-6 && abs(p.y - 300) < 1e-6)
        #expect(v.fitZoom == fit.fitZoom && v.zoom == 150)
    }

    @Test func clickOnCharacterFindsDeskBehindIt() {
        let members = [OfficePlan.Member(id: "a", roomKey: "/a")]
        let plan = OfficePlan.make(members, slots: OfficePlan.assignSlots(members, previous: [:]))
        let desk = plan.rooms[0].desks[0]
        let viewport = OfficeViewport.fitting(plan.bounds, height: OfficePlan.wallHeight, viewSize: size)
        let head = viewport.project(x: desk.x, y: 0.9, z: desk.z, viewSize: size)
        #expect(plan.desk(atViewX: head.x, y: head.y, viewport: viewport, viewSize: size) == "a")
        #expect(plan.desk(atViewX: 1, y: 1, viewport: viewport, viewSize: size) == nil)
    }

    @Test func detailLevelsByZoom() {
        #expect(OfficeDetail.level(zoom: 20) == .far)
        #expect(OfficeDetail.level(zoom: 70) == .medium)
        #expect(OfficeDetail.level(zoom: 150) == .near)
    }

    @Test(arguments: [(1440.0, 900.0), (2560.0, 1440.0)])
    func pinchInNeverZoomsOutFromFit(width: Double, height: Double) {
        let members = [OfficePlan.Member(id: "a", roomKey: "/a")]
        let plan = OfficePlan.make(members, slots: OfficePlan.assignSlots(members, previous: [:]))
        let view = (width: width, height: height)
        let fit = OfficeViewport.fitting(plan.bounds, height: OfficePlan.wallHeight, viewSize: view)
        let limits = OfficeViewport.zoomLimits(fit: fit)
        #expect(limits.contains(fit.zoom))
        var viewport = fit
        viewport.zoom(by: 1.05, anchorX: width / 2, anchorY: height / 2, viewSize: view, limits: limits, within: plan.bounds)
        #expect(viewport.zoom > fit.zoom)
    }

    @Test(arguments: [60.0, 130.0])
    func clickingBubbleOrCardOpensItsDesk(zoom: Double) {
        let members = [OfficePlan.Member(id: "a", roomKey: "/a"), OfficePlan.Member(id: "b", roomKey: "/a")]
        let plan = OfficePlan.make(members, slots: OfficePlan.assignSlots(members, previous: [:]))
        let desk = plan.rooms[0].desks[1]
        let fit = OfficeViewport.fitting(plan.bounds, height: OfficePlan.wallHeight, viewSize: size)
        let viewport = OfficeViewport.focusing(x: desk.x, z: desk.z, zoom: zoom, fit: fit)
        let detail = OfficeDetail.level(zoom: zoom)
        let anchor = OfficeOverlay.anchor(desk, viewport: viewport, viewSize: size)
        let bubbleY = anchor.y - OfficeOverlay.bubbleOffset(detail)
        #expect(plan.desk(atViewX: anchor.x, y: bubbleY, viewport: viewport, viewSize: size, detail: detail, waiting: ["b"]) == "b")
        let cardY = anchor.y - OfficeOverlay.cardOffset
        #expect(plan.desk(atViewX: anchor.x + 20, y: cardY, viewport: viewport, viewSize: size, detail: detail, waiting: []) == "b")
    }
}
