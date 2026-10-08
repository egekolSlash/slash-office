import Testing
@testable import AgentOfficeCore

/// Odaklanan kamera köylüyü takip eder: hedef köylünün o anki yerini (gövdesini) ortalar.
@Suite struct CameraFollowTests {
    let size = (width: 900.0, height: 600.0)

    @Test(arguments: [false, true]) func targetCentersTheVillagerBody(seated: Bool) {
        let fit = OfficeViewport.fitting(PlanRect(minX: 0, minZ: 0, maxX: 12, maxZ: 10), height: 1.6, viewSize: size)
        for zoom in [60.0, 120, 220] {
            let v = CameraFollow.target(x: 4.2, z: 6.5, seated: seated, zoom: zoom, fit: fit)
            let p = v.project(x: 4.2, y: seated ? CameraFollow.seatedBody : CameraFollow.standingBody, z: 6.5, viewSize: size)
            #expect(abs(p.x - 450) < 0.5 && abs(p.y - 300) < 0.5)
            #expect(v.zoom == zoom)
        }
    }

    /// Köylü odadan çıkınca (ya da oturumu kaldırılınca) takip biter.
    @Test func followEndsWhenVillagerLeaves() {
        #expect(CameraFollow.shouldContinue(AvatarSim.Position(x: 1, z: 1, seated: true, inRoom: true)))
        #expect(!CameraFollow.shouldContinue(AvatarSim.Position(x: 1, z: 1, seated: false, inRoom: false)))
        #expect(!CameraFollow.shouldContinue(nil))
    }

    /// Köylü yerinde dururken hedef güncellenmez (kamera boşuna ekran hızına çıkmasın).
    @Test func smallDriftDoesNotMoveTheCamera() {
        let fit = OfficeViewport.fitting(PlanRect(minX: 0, minZ: 0, maxX: 12, maxZ: 10), height: 1.6, viewSize: size)
        let current = CameraFollow.target(x: 4, z: 6, seated: true, zoom: 120, fit: fit)
        let same = CameraFollow.target(x: 4.001, z: 6, seated: true, zoom: 120, fit: fit)
        let moved = CameraFollow.target(x: 4.3, z: 6, seated: true, zoom: 120, fit: fit)
        #expect(!CameraFollow.needsUpdate(current: current, next: same))
        #expect(CameraFollow.needsUpdate(current: current, next: moved))
    }

    @Test func simReportsVillagerPosition() throws {
        let members = [OfficePlan.Member(id: "a", roomKey: "/a")]
        let plan = OfficePlan.make(members, slots: OfficePlan.assignSlots(members, previous: [:]))
        var sim = AvatarSim(skeleton: VillagerSkeletonTests.skeleton)
        sim.sync(plan: plan, desks: ["a": AvatarDeskState(state: .working(tool: nil), kind: .claude)], looks: [:],
                 projectColors: [:], live: false)
        let position = try #require(sim.position(of: "a"))
        #expect(position.inRoom && position.seated)
        #expect(sim.position(of: "nobody") == nil)
    }
}
