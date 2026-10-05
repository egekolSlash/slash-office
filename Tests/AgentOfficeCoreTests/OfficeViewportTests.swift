import Testing
@testable import AgentOfficeCore

@Suite struct OfficeViewportTests {
    let size = (width: 800.0, height: 600.0)

    @Test func centerProjectsToViewCenterAndAxesFollowIsometry() {
        let center = OfficeViewport.screenPlane(x: 2, y: 0, z: 1)
        let viewport = OfficeViewport(centerX: center.x, centerY: center.y, zoom: 50)
        let p = viewport.project(x: 2, y: 0, z: 1, viewSize: size)
        #expect(abs(p.x - 400) < 1e-9 && abs(p.y - 300) < 1e-9)
        let up = viewport.project(x: 2, y: 1, z: 1, viewSize: size)
        let nextX = viewport.project(x: 3, y: 0, z: 1, viewSize: size)
        let nextZ = viewport.project(x: 2, y: 0, z: 2, viewSize: size)
        #expect(up.y < p.y && abs(up.x - p.x) < 1e-9)
        #expect(nextX.x > p.x && nextX.y > p.y)
        #expect(nextZ.x < p.x && nextZ.y > p.y)
    }

    @Test(arguments: [0.0, 0.45, 1.2])
    func pointAtHeightInvertsProject(height: Double) {
        let viewport = OfficeViewport(centerX: 0.3, centerY: -1.1, zoom: 37)
        let view = viewport.project(x: 4.2, y: height, z: 1.7, viewSize: size)
        let back = viewport.point(atX: view.x, y: view.y, height: height, viewSize: size)
        #expect(abs(back.x - 4.2) < 1e-9 && abs(back.z - 1.7) < 1e-9)
    }

    @Test func panMovesContentWithFinger() {
        var viewport = OfficeViewport(centerX: 0, centerY: 0, zoom: 40)
        let before = viewport.project(x: 1, y: 0, z: 1, viewSize: size)
        viewport.pan(dx: 30, dy: -20)
        let after = viewport.project(x: 1, y: 0, z: 1, viewSize: size)
        #expect(abs(after.x - before.x - 30) < 1e-9 && abs(after.y - before.y + 20) < 1e-9)
    }

    @Test func zoomKeepsAnchorFixedAndRespectsLimits() {
        var viewport = OfficeViewport(centerX: 1, centerY: -2, zoom: 40)
        let anchor = (x: 620.0, y: 140.0)
        let ground = viewport.point(atX: anchor.x, y: anchor.y, height: 0, viewSize: size)
        viewport.zoom(by: 2, anchorX: anchor.x, anchorY: anchor.y, viewSize: size, limits: 10...200)
        #expect(viewport.zoom == 80)
        let again = viewport.project(x: ground.x, y: 0, z: ground.z, viewSize: size)
        #expect(abs(again.x - anchor.x) < 1e-6 && abs(again.y - anchor.y) < 1e-6)
        viewport.zoom(by: 100, anchorX: 0, anchorY: 0, viewSize: size, limits: 10...200)
        #expect(viewport.zoom == 200)
    }

    @Test(arguments: [(800.0, 600.0), (240.0, 220.0), (320.0, 900.0)])
    func fittingKeepsEveryRoomCornerInsideView(width: Double, height: Double) {
        let members = (0..<9).map { OfficePlan.Member(id: "s\($0)", roomKey: "/p\($0 % 5)") }
        let plan = OfficePlan.make(members, slots: OfficePlan.assignSlots(members, previous: [:]))
        let view = (width: width, height: height)
        let viewport = OfficeViewport.fitting(plan.bounds, height: OfficePlan.wallHeight, viewSize: view)
        for room in plan.rooms {
            for (x, z) in [(room.x, room.z), (room.x + Double(room.width), room.z + Double(room.depth))] {
                for y in [0.0, OfficePlan.wallHeight] {
                    let p = viewport.project(x: x, y: y, z: z, viewSize: view)
                    #expect(p.x >= -0.5 && p.x <= width + 0.5 && p.y >= -0.5 && p.y <= height + 0.5)
                }
            }
        }
    }

    @Test func fittingEmptyPlanIsFinite() {
        let viewport = OfficeViewport.fitting(.zero, height: 1.6, viewSize: (0, 0))
        #expect(viewport.zoom.isFinite && viewport.zoom > 0 && viewport.centerX.isFinite)
        let limits = OfficeViewport.zoomLimits(fit: viewport)
        #expect(limits.lowerBound > 0 && limits.upperBound >= limits.lowerBound)
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
        viewport.zoom(by: 1.05, anchorX: width / 2, anchorY: height / 2, viewSize: view, limits: limits)
        #expect(viewport.zoom > fit.zoom)
    }
}
