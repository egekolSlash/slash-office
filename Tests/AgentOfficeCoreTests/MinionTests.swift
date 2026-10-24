import Foundation
import simd
import Testing
@testable import AgentOfficeCore

@Suite struct MinionTests {
    func plan(_ ids: [String]) -> OfficePlan {
        let members = ids.map { OfficePlan.Member(id: $0, roomKey: "/r") }
        return OfficePlan.make(members, slots: OfficePlan.assignSlots(members, previous: [:]))
    }

    func run(_ sim: inout MinionSim, seconds: Double, step: Double = 1.0 / 30) {
        for _ in 0..<Int(seconds / step) { sim.tick(dt: step) }
    }

    func desk(_ plan: OfficePlan, _ id: String) -> (room: OfficePlan.Room, desk: OfficePlan.Desk) {
        let room = plan.rooms.first { $0.desks.contains { $0.id == id } }!
        return (room, room.desks.first { $0.id == id }!)
    }

    @Test func popsFromTheScreenLandsAndWalksAroundTheDesk() {
        let plan = plan(["a"])
        var sim = MinionSim()
        sim.sync(plan: plan, jobs: ["a": ["j1"]])
        sim.tick(dt: 0.05)
        let first = try! #require(sim.instances.first)
        #expect(first.motion == .air)
        #expect(first.position.y > 0.6)       // ekrandan çıkıyor
        #expect(first.scale < 1)
        run(&sim, seconds: 3)
        let walking = try! #require(sim.instances.first)
        #expect(walking.position.y == 0)
        #expect(walking.scale == 1)
        // Halkada: masanın merkezinden masa ölçüsünden uzak, ama komşu masaya kadar değil.
        let (_, d) = desk(plan, "a")
        let dist = hypot(Double(walking.position.x) - d.x, Double(walking.position.z) - d.z)
        #expect(dist > DeskGeometry.deskHalfWidth + 0.2)
        #expect(dist < 1.2)
    }

    @Test func finishedJobWalksBackAndDivesIn() {
        let plan = plan(["a"])
        var sim = MinionSim()
        sim.sync(plan: plan, jobs: ["a": ["j1"]])
        run(&sim, seconds: 6)
        sim.sync(plan: plan, jobs: ["a": []])
        var sawDive = false
        for _ in 0..<600 {
            sim.tick(dt: 1.0 / 30)
            if let m = sim.instances.first, m.motion == .air { sawDive = true }
            if sim.isEmpty { break }
        }
        #expect(sawDive)
        #expect(sim.isEmpty)
    }

    @Test func atMostFourPerDeskAndSlotsReused() {
        let plan = plan(["a", "b"])
        var sim = MinionSim()
        sim.sync(plan: plan, jobs: ["a": ["1", "2", "3", "4", "5", "6"], "b": ["x"], "ghost": ["g"]])
        run(&sim, seconds: 3)
        let ids = sim.instances.map(\.id)
        #expect(ids.filter { $0.hasPrefix("a/") }.count == 4)
        #expect(ids.filter { $0.hasPrefix("b/") }.count == 1)
        #expect(!ids.contains { $0.hasPrefix("ghost/") })
    }

    @Test func removedDeskDropsItsMinionsImmediately() {
        var sim = MinionSim()
        sim.sync(plan: plan(["a", "b"]), jobs: ["a": ["1"], "b": ["2"]])
        run(&sim, seconds: 1)
        sim.sync(plan: plan(["b"]), jobs: ["b": ["2"]])
        #expect(sim.instances.map(\.id) == ["b/2"])
    }

    @Test func deterministic() {
        func positions() -> [SIMD3<Float>] {
            var sim = MinionSim()
            sim.sync(plan: plan(["a"]), jobs: ["a": ["1", "2"]])
            run(&sim, seconds: 9)
            return sim.instances.map(\.position)
        }
        #expect(positions() == positions())
    }

    @Test func ringWrapsAndShortestPath() {
        let p = MinionSim.perimeter
        #expect(abs(MinionSim.wrap(-0.1) - (p - 0.1)) < 1e-9)
        #expect(abs(MinionSim.shortest(from: 0.1, to: p - 0.1) + 0.2) < 1e-9)
        for s in stride(from: 0.0, to: p, by: 0.37) {
            let q = MinionSim.ringPoint(s)
            #expect(abs(MinionSim.ringS(local: (q.x, q.z)) - s) < 1e-6)
        }
    }

    @Test func walkingLegsSwingOppositeAndPivotsStayPut() {
        let pivots: [SIMD3<Float>] = [SIMD3(0, 0.1, 0), SIMD3(0, 0.2, 0), SIMD3(0.03, 0.09, 0), SIMD3(-0.03, 0.09, 0), SIMD3(0, 0.1, -0.03)]
        let m = MinionInstance(id: "x", position: .zero, facing: 0, scale: 1, motion: .walk(cycle: 0.25), time: 0, seed: 0)
        let bones = MinionPose.bones(for: m, pivots: pivots)
        #expect(bones.count == 5)
        // Bacak ucu (pivotun altı) zıt yönlere gider.
        let foot = SIMD4<Float>(0.03, 0, 0, 1), footR = SIMD4<Float>(-0.03, 0, 0, 1)
        #expect((bones[2] * foot).z * (bones[3] * footR).z < 0)
        // Dururken kafa pivotu yerinde kalır (yalnız dönüş).
        let idle = MinionInstance(id: "x", position: .zero, facing: 0, scale: 1, motion: .idle, time: 1, seed: 0)
        let head = MinionPose.bones(for: idle, pivots: pivots)[1] * SIMD4(pivots[1], 1)
        #expect(simd_distance(SIMD3(head.x, head.y, head.z), pivots[1]) < 0.01)
    }

    /// Depodaki paket: kemikler, parçalar, boy ve poligon bütçesi.
    @Test func realPackIsSane() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = try #require(MinionArt.find(bundleResources: nil, repoRoot: root))
        let art = try MinionArt.load(directory: dir)
        #expect(art.bones == MinionArt.boneNames)
        #expect(abs(art.height - 0.5) < 0.01)
        let triangles = art.meshes.values.reduce(0) { $0 + $1.indices.count / 3 }
        #expect(triangles < 20_000)
        #expect(art.parts.contains { $0.mode == .albedo && $0.texture != nil })
        let top = art.meshes.values.flatMap { m in stride(from: 1, to: m.positions.count, by: 3).map { m.positions[$0] } }.max() ?? 0
        #expect(abs(top - art.height) < 0.02)
    }
}
