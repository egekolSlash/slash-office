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

    /// Kare başı takip adımı kare hızından bağımsız: 30 ve 120 fps'te aynı sürede aynı yere gelir; sonunda hedefe oturur.
    @Test func followStepIsFrameRateIndependentAndArrives() {
        let fit = OfficeViewport.fitting(PlanRect(minX: 0, minZ: 0, maxX: 12, maxZ: 10), height: 1.6, viewSize: size)
        let start = CameraFollow.target(x: 2, z: 3, seated: true, zoom: 100, fit: fit)
        let goal = CameraFollow.target(x: 6, z: 7, seated: false, zoom: 160, fit: fit)
        func run(fps: Double, seconds: Double) -> (OfficeViewport, Bool) {
            var v = start, arrived = false
            for _ in 0..<Int(seconds * fps) { (v, arrived) = CameraFollow.step(v, toward: goal, dt: 1 / fps) }
            return (v, arrived)
        }
        let (slow, _) = run(fps: 30, seconds: 0.2), (fast, _) = run(fps: 120, seconds: 0.2)
        #expect(abs(slow.targetX - fast.targetX) < 0.01 && abs(slow.zoom - fast.zoom) < 0.5)
        let (end, arrived) = run(fps: 60, seconds: 2)
        #expect(arrived && end == goal)
    }

    /// Yürüyen köylüyü her karede takip eden kamerada köylünün ekrandaki yeri ileri geri sıçramaz: kayma tek yönlü
    /// ve kare kare düzgün (eski 5 Hz hedef güncellemesi testere dişi titreme yapıyordu).
    @Test func walkingVillagerStaysSmoothOnScreen() {
        let fit = OfficeViewport.fitting(PlanRect(minX: 0, minZ: 0, maxX: 12, maxZ: 10), height: 1.6, viewSize: size)
        var v = CameraFollow.target(x: 2, z: 5, seated: false, zoom: 150, fit: fit)
        var xs: [Double] = []
        let fps = 60.0
        for frame in 0..<120 {
            let x = 2 + 1.2 * Double(frame + 1) / fps  // 1,2 m/sn
            v = CameraFollow.step(v, toward: CameraFollow.target(x: x, z: 5, seated: false, zoom: 150, fit: fit), dt: 1 / fps).viewport
            xs.append(v.project(x: x, y: CameraFollow.standingBody, z: 5, viewSize: size).x)
        }
        let deltas = zip(xs.dropFirst(), xs).map { $0 - $1 }
        #expect(deltas.allSatisfy { $0 >= -0.001 })
        #expect(zip(deltas.dropFirst(), deltas).allSatisfy { abs($0 - $1) < 0.5 })
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
