import Foundation
import Testing
import simd
@testable import AgentOfficeCore

@Suite struct VillagerSkeletonTests {
    /// Tek kemikli sahte klipler: her karede x ötelemesi `values[f]`.
    static func clip(_ values: [Float]) -> ArtClip {
        ArtClip(frames: values.count, matrices: values.flatMap { x -> [Float] in
            [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, 0, 0, 1]
        })
    }

    static let skeleton = VillagerSkeleton(art: OfficeArtFile(
        bones: ["Root"],
        clips: ["idle": clip([0, 1, 2]), "walk": clip([10, 10]), "wave": clip([-4, -4]),
                "sitType": clip([3, 3]), "sitDoze": clip([5, 5])],
        villager: OfficeArtFile.emptyMesh, props: [:]))

    func x(_ m: [simd_float4x4]) -> Float { m[0].columns.3.x }

    @Test func clipLoopsAndInterpolates() {
        let s = Self.skeleton
        #expect(abs(x(s.matrices(clip: .idle, time: 0)) - 0) < 1e-4)
        #expect(abs(x(s.matrices(clip: .idle, time: 1.0 / 48)) - 0.5) < 1e-4)
        #expect(abs(x(s.matrices(clip: .idle, time: 1.5 / 24)) - 1.5) < 1e-4)
        // Dönem (kare − 1) / 24: son kare ilkine eşittir, döngü oradan başa sarar.
        #expect(abs(x(s.matrices(clip: .idle, time: 2.0 / 24)) - 0) < 1e-4)
        #expect(abs(x(s.matrices(clip: .idle, time: 2.5 / 24)) - 0.5) < 1e-4)
        #expect(s.boneCount == 1)
    }

    @Test func missingClipGivesIdentity() {
        let s = VillagerSkeleton(art: OfficeArtFile(bones: ["Root", "Hips"], clips: [:], villager: OfficeArtFile.emptyMesh, props: [:]))
        #expect(s.matrices(clip: .walk, time: 0.3) == [matrix_identity_float4x4, matrix_identity_float4x4])
    }

    @Test func crossfadeBlendsLinearly() {
        var a = AvatarInstance(id: "a", clip: .idle)
        a.play(.walk, skeleton: Self.skeleton)
        #expect(abs(x(Self.skeleton.pose(of: a)) - 0) < 1e-4)
        a.advance(dt: AvatarInstance.fade / 2)
        // idle t=fade/2 (0.125 s = 3 kare → döngüde 1) ile walk (10) yarı yarıya.
        let idle = x(Self.skeleton.matrices(clip: .idle, time: AvatarInstance.fade / 2))
        #expect(abs(x(Self.skeleton.pose(of: a)) - (idle + 10) / 2) < 1e-3)
        a.advance(dt: AvatarInstance.fade)
        #expect(abs(x(Self.skeleton.pose(of: a)) - 10) < 1e-4)
        #expect(a.blend == 1)
    }

    @Test func crossfadeInterruptedMidway() {
        var a = AvatarInstance(id: "a", clip: .idle)
        a.play(.walk, skeleton: Self.skeleton)
        a.advance(dt: AvatarInstance.fade * 0.4)
        let before = x(Self.skeleton.pose(of: a))
        a.play(.wave, skeleton: Self.skeleton)
        #expect(abs(x(Self.skeleton.pose(of: a)) - before) < 1e-4, "geçiş kesilince sıçrama")
        a.advance(dt: AvatarInstance.fade * 0.5)
        #expect(abs(x(Self.skeleton.pose(of: a)) - (before + -4) / 2) < 1e-3)
        a.advance(dt: AvatarInstance.fade)
        #expect(abs(x(Self.skeleton.pose(of: a)) - -4) < 1e-4)
    }

    @Test func playingSameClipKeepsTime() {
        var a = AvatarInstance(id: "a", clip: .idle)
        a.advance(dt: 0.03)
        a.play(.idle, skeleton: Self.skeleton)
        #expect(a.clipTime == 0.03 && a.blend == 1)
    }

    @Test func blendRotatesThroughQuaternion() {
        // 0° ve 90° arası yarı geçiş 45° olmalı (matris lerp'i gibi büzülmemeli).
        let r90 = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0)))
        let flat: (simd_float4x4) -> [Float] = { m in (0..<4).flatMap { c in (0..<4).map { m[c][$0] } } }
        let s = VillagerSkeleton(art: OfficeArtFile(bones: ["Root"],
            clips: ["idle": ArtClip(frames: 1, matrices: flat(matrix_identity_float4x4)), "walk": ArtClip(frames: 1, matrices: flat(r90))],
            villager: OfficeArtFile.emptyMesh, props: [:]))
        var a = AvatarInstance(id: "a", clip: .idle)
        a.play(.walk, skeleton: s)
        a.advance(dt: AvatarInstance.fade / 2)
        let m = s.pose(of: a)[0]
        #expect(abs(simd_length(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z)) - 1) < 1e-4)
        #expect(abs(m.columns.0.x - cos(Float.pi / 4)) < 1e-3)
    }
}

@Suite struct AvatarSimTests {
    func plan(_ ids: [String]) -> OfficePlan {
        let members = ids.map { OfficePlan.Member(id: $0, roomKey: "/r") }
        return OfficePlan.make(members, slots: OfficePlan.assignSlots(members, previous: [:]))
    }

    func sim() -> AvatarSim { AvatarSim(skeleton: VillagerSkeletonTests.skeleton) }

    func desks(_ pairs: [(String, AgentState)], kind: SessionKind = .claude) -> [String: AvatarDeskState] {
        Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, AvatarDeskState(state: $0.1, kind: kind)) })
    }

    func position(_ p: PlanPoint) -> SIMD3<Float> { SIMD3(Float(p.x), 0, Float(p.z)) }

    @Test func firstLoadPlacesInPlace() {
        var s = sim()
        let p = plan(["a", "b"])
        s.sync(plan: p, desks: desks([("a", .working(tool: nil)), ("b", .waiting(.permission("Bash")))]),
               looks: [:], projectColors: [:], live: false)
        #expect(s.instances.map(\.id) == ["a", "b"])
        let room = p.rooms[0]
        let a = s.instances[0], b = s.instances[1]
        #expect(a.position == position(room.seat(for: room.desks[0])) && a.clip == .sitType)
        #expect(b.position == position(room.standSpot(for: room.desks[1])) && b.clip == .wave && b.waving)
        #expect(!s.isMoving)
    }

    @Test func liveNewSessionWalksInFromTheDoor() {
        var s = sim()
        let p = plan(["a"])
        s.sync(plan: p, desks: desks([("a", .working(tool: nil))]), looks: [:], projectColors: [:], live: true)
        let room = p.rooms[0]
        #expect(s.instances[0].position == position(room.doorOutside))
        #expect(s.instances[0].clip == .walk)
        #expect(s.isMoving)
        for _ in 0..<600 { s.tick(dt: 1.0 / 60) }
        #expect(!s.isMoving)
        #expect(s.instances[0].position == position(room.seat(for: room.desks[0])))
        #expect(s.instances[0].clip == .sitType)
        #expect(s.instances[0].facing == 0)
    }

    @Test func walkingFacesTheDirectionOfTravel() {
        var s = sim()
        s.sync(plan: plan(["a"]), desks: desks([("a", .working(tool: nil))]), looks: [:], projectColors: [:], live: true)
        let start = s.instances[0].position
        s.tick(dt: 0.05)
        let moved = s.instances[0].position - start
        let f = s.instances[0].facing
        #expect(simd_length(moved) > 0.01)
        #expect(abs(sin(f) - moved.x / simd_length(moved)) < 1e-3 && abs(cos(f) - moved.z / simd_length(moved)) < 1e-3)
    }

    @Test func awayRemoves() {
        var s = sim()
        let p = plan(["a", "b"])
        s.sync(plan: p, desks: desks([("a", .working(tool: nil)), ("b", .exited)]), looks: [:], projectColors: [:], live: false)
        #expect(s.instances.map(\.id) == ["a"])
        // Canlı: çıkış yürüyüşü bitince kalkar.
        s.sync(plan: p, desks: desks([("a", .exited), ("b", .exited)]), looks: [:], projectColors: [:], live: true)
        #expect(s.instances.map(\.id) == ["a"] && s.isMoving)
        for _ in 0..<600 { s.tick(dt: 1.0 / 60) }
        #expect(s.instances.isEmpty)
        // Plandan çıkan masa: hemen kalkar.
        s.sync(plan: p, desks: desks([("a", .working(tool: nil))]), looks: [:], projectColors: [:], live: false)
        s.sync(plan: plan(["b"]), desks: desks([("b", .working(tool: nil))]), looks: [:], projectColors: [:], live: false)
        #expect(s.instances.map(\.id) == ["b"])
    }

    @Test func idleShellHasNoAvatar() {
        var s = sim()
        s.sync(plan: plan(["a"]), desks: desks([("a", .idle)], kind: .shell), looks: [:], projectColors: [:], live: false)
        #expect(s.instances.isEmpty)
    }

    @Test func lookChangesAreReflected() {
        var s = sim()
        let p = plan(["a"])
        let d = desks([("a", .working(tool: nil))])
        s.sync(plan: p, desks: d, looks: [:], projectColors: ["/r": (0.1, 0.2, 0.3)], live: false)
        #expect(s.instances[0].look == AvatarLook.default(for: "a"))
        var look = AvatarLook.default(for: "a")
        look.shirtColor = nil
        look.glasses.toggle()
        s.sync(plan: p, desks: d, looks: ["a": look], projectColors: ["/r": (0.1, 0.2, 0.3)], live: false)
        #expect(s.instances[0].look == look)
        #expect(s.instances[0].shirtColor == SIMD3(0.1, 0.2, 0.3))
        look.shirtColor = 2
        s.sync(plan: p, desks: d, looks: ["a": look], projectColors: ["/r": (0.1, 0.2, 0.3)], live: false)
        let c = AvatarLook.shirtColors[2]
        #expect(s.instances[0].shirtColor == SIMD3(Float(c.red), Float(c.green), Float(c.blue)))
    }

    @Test func stateChangeWalksToTheNewSpot() {
        var s = sim()
        let p = plan(["a"])
        s.sync(plan: p, desks: desks([("a", .working(tool: nil))]), looks: [:], projectColors: [:], live: false)
        s.sync(plan: p, desks: desks([("a", .waiting(.permission("Bash")))]), looks: [:], projectColors: [:], live: true)
        #expect(s.isMoving && s.instances[0].clip == .walk)
        for _ in 0..<600 { s.tick(dt: 1.0 / 60) }
        let room = p.rooms[0]
        #expect(s.instances[0].position == position(room.standSpot(for: room.desks[0])))
        #expect(s.instances[0].clip == .wave && s.instances[0].waving)
    }
}
