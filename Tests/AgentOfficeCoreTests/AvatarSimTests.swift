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
                "sitType": clip([3, 3]), "sitDoze": clip([5, 5]), "sitDown": clip([0, 7]), "standUp": clip([7, 0]),
                "cheer": clip([1, 9])],
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

    /// Tek seferlik klip süresini aşınca son karede kalır (başa sarıp ters poza sıçramaz).
    @Test func oneShotClipsHoldTheirLastFrame() {
        let s = Self.skeleton
        #expect(abs(x(s.matrices(clip: .sitDown, time: AvatarClip.sitDown.duration * 1.5)) - 7) < 1e-4)
        #expect(abs(x(s.matrices(clip: .standUp, time: AvatarClip.standUp.duration + 0.3)) - 0) < 1e-4)
        // Döngüler hâlâ sarar.
        #expect(abs(x(s.matrices(clip: .idle, time: 2.0 / 24)) - 0) < 1e-4)
        // sitDown biter, döngüye geçilir: geçişin ilk anı sitDown'un son pozunda.
        var a = AvatarInstance(id: "a", clip: .idle)
        a.play(.sitDown, skeleton: s)
        a.advance(dt: AvatarInstance.fade)
        a.advance(dt: AvatarClip.sitDown.duration)
        a.play(.sitDoze, skeleton: s)
        #expect(abs(x(s.pose(of: a)) - 7) < 1e-3)
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

    func desks(_ pairs: [(String, AgentState)], kind: SessionKind = .claude, finished: Set<String> = []) -> [String: AvatarDeskState] {
        Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, AvatarDeskState(state: $0.1, kind: kind, unseenFinish: finished.contains($0.0))) })
    }

    func position(_ p: PlanPoint) -> SIMD3<Float> { SIMD3(Float(p.x), 0, Float(p.z)) }
    func near(_ a: SIMD3<Float>, _ p: PlanPoint, _ tolerance: Float = 0.02) -> Bool { simd_length(a - position(p)) < tolerance }

    /// `seconds` boyunca 1/60 sn adımlarla ilerletir; her adımda `each` çağrılır.
    func run(_ s: inout AvatarSim, _ seconds: Double, each: (AvatarSim) -> Void = { _ in }) {
        for _ in 0..<Int(seconds * 60) { s.tick(dt: 1.0 / 60); each(s) }
    }

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

    @Test func liveNewSessionWalksInFromTheDoorAndSitsDown() {
        var s = sim()
        let p = plan(["a"])
        s.sync(plan: p, desks: desks([("a", .working(tool: nil))]), looks: [:], projectColors: [:], live: true)
        let room = p.rooms[0]
        #expect(s.instances[0].position == position(room.doorOutside))
        #expect(s.instances[0].clip == .walk && s.isMoving)
        var clips: [AvatarClip] = []
        run(&s, 8) { if clips.last != $0.instances[0].clip { clips.append($0.instances[0].clip) } }
        #expect(clips.contains(.sitDown))
        #expect(near(s.instances[0].position, room.seat(for: room.desks[0])))
        // Masada koridora bakar.
        #expect(s.instances[0].clip.seated && abs(Double(s.instances[0].facing) - room.seatFacing(for: room.desks[0])) < 1e-5)
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
        s.sync(plan: p, desks: desks([("a", .exited), ("b", .exited)]), looks: [:], projectColors: [:], live: true)
        run(&s, 0.2)
        #expect(s.instances.map(\.id) == ["a"] && s.isMoving)
        run(&s, 15)
        #expect(s.instances.isEmpty)
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
        run(&s, 10)
        let room = p.rooms[0]
        #expect(near(s.instances[0].position, room.standSpot(for: room.desks[0])))
        #expect([AvatarClip.wave, .waitTap, .lookAround].contains(s.instances[0].clip) && s.instances[0].waving)
    }

    @Test func sittingUsesSitDownAndStandUp() {
        var s = sim()
        let p = plan(["a"])
        s.sync(plan: p, desks: desks([("a", .working(tool: nil))]), looks: [:], projectColors: [:], live: false)
        s.sync(plan: p, desks: desks([("a", .waiting(.question("?")))]), looks: [:], projectColors: [:], live: true)
        var clips: [AvatarClip] = []
        run(&s, 6) { if clips.last != $0.instances[0].clip { clips.append($0.instances[0].clip) } }
        #expect(clips.first == .standUp)
        #expect(clips.contains(.walk))
        // Kalkarken yürümez: standUp bitene kadar yer değiştirmez.
        var s2 = sim()
        s2.sync(plan: p, desks: desks([("a", .working(tool: nil))]), looks: [:], projectColors: [:], live: false)
        let seat = s2.instances[0].position
        s2.sync(plan: p, desks: desks([("a", .waiting(.question("?")))]), looks: [:], projectColors: [:], live: true)
        run(&s2, AvatarClip.standUp.duration * 0.8)
        #expect(s2.instances[0].position == seat)
    }

    @Test func stateChangeMidActionStandsUpThenWalks() {
        var s = sim()
        let p = plan(["a", "b"])
        s.sync(plan: p, desks: desks([("a", .idle), ("b", .working(tool: nil))]), looks: [:], projectColors: [:], live: false)
        // Boştaki köylü bir noktaya gidip yerleşene kadar.
        var wandered = false
        for _ in 0..<(120 * 60) {
            s.tick(dt: 1.0 / 60)
            if !s.isMoving, let a = s.instances.first(where: { $0.id == "a" }),
               !near(a.position, p.rooms[0].seat(for: p.rooms[0].desks[0]), 0.3) { wandered = true; break }
        }
        #expect(wandered)
        // Soru gelir: masanın yanına yürür, sıçramadan (adım başına en fazla hız × dt).
        s.sync(plan: p, desks: desks([("a", .waiting(.question("?"))), ("b", .working(tool: nil))]), looks: [:], projectColors: [:], live: true)
        var last = s.instances.first { $0.id == "a" }!.position
        var maxStep: Float = 0
        run(&s, 15) { sim in
            let now = sim.instances.first { $0.id == "a" }!.position
            maxStep = max(maxStep, simd_length(now - last)); last = now
        }
        #expect(maxStep < Float(AvatarRoute.speed / 60) * 1.5 + 0.02)
        let room = p.rooms[0]
        #expect(near(s.instances.first { $0.id == "a" }!.position, room.standSpot(for: room.desks[0])))
    }

    @Test func idleVillagersReserveDistinctSpots() {
        var s = sim()
        let ids = (0..<6).map { "i\($0)" }
        let p = plan(ids)
        s.sync(plan: p, desks: desks(ids.map { ($0, AgentState.idle) }), looks: [:], projectColors: [:], live: false)
        var collision = false
        run(&s, 240) { sim in
            let spots = sim.reservedSpots.values
            if Set(spots).count != spots.count { collision = true }
        }
        #expect(!collision)
        #expect(s.everReservedCount > 0)
    }

    @Test func roomChangeWhileWanderingReplans() {
        var s = sim()
        var ids = ["a", "b"]
        s.sync(plan: plan(ids), desks: desks(ids.map { ($0, AgentState.idle) }), looks: [:], projectColors: [:], live: false)
        run(&s, 40)
        // Oda büyür (masa eklenir): kimse engelin içinde kalmaz, kimse ışınlanıp kaybolmaz.
        ids += ["c", "d", "e"]
        let bigger = plan(ids)
        s.sync(plan: bigger, desks: desks(ids.map { ($0, AgentState.idle) }), looks: [:], projectColors: [:], live: true)
        let nav = RoomNav(room: bigger.rooms[0])
        run(&s, 30) { sim in
            for a in sim.instances where ["a", "b"].contains(a.id) {
                let pt = PlanPoint(x: Double(a.position.x), z: Double(a.position.z))
                // Taburede ya da koltukta oturmak (mobilyanın içi) ve kapı eşiği serbest.
                let seats = bigger.rooms[0].desks.map { bigger.rooms[0].seat(for: $0) }
                    + bigger.rooms[0].spots.filter { $0.kind == .sofa }.map { PlanPoint(x: $0.x, z: $0.z) }
                #expect(nav.isFree(pt) || seats.contains { $0.distance(to: pt) < 0.7 } || pt.distance(to: bigger.rooms[0].doorInside) < 0.5,
                        "\(a.id) engelde: \(pt)")
            }
        }
    }

    @Test func cheerOncePerFinish() {
        var s = sim()
        let p = plan(["a"])
        s.sync(plan: p, desks: desks([("a", .working(tool: nil))]), looks: [:], projectColors: [:], live: false)
        s.sync(plan: p, desks: desks([("a", .idle)], finished: ["a"]), looks: [:], projectColors: [:], live: true)
        var cheers = 0, last: AvatarClip?
        run(&s, 10) { sim in
            let c = sim.instances[0].clip
            if c == .cheer && last != .cheer { cheers += 1 }
            last = c
        }
        #expect(cheers == 1)
        // Görüldü (unseenFinish kalktı), sonra aynı bitmiş durum: tekrar sevinmez.
        s.sync(plan: p, desks: desks([("a", .idle)]), looks: [:], projectColors: [:], live: true)
        run(&s, 10) { sim in if sim.instances[0].clip == .cheer { cheers += 1 } }
        #expect(cheers == 1)
    }

    /// Kalkarken ertelenen sevinç, kullanıcı hemen cevap verip köylü masaya dönerse çöpe gider; sonraki bir
    /// beklemede (ya da bitki/sebilde) yanlış zamanda oynamaz.
    @Test func staleCheerIsDropped() {
        var s = sim()
        let p = plan(["a"])
        s.sync(plan: p, desks: desks([("a", .working(tool: nil))]), looks: [:], projectColors: [:], live: false)
        s.sync(plan: p, desks: desks([("a", .idle)], finished: ["a"]), looks: [:], projectColors: [:], live: true)
        run(&s, 0.35)                                           // sevinç kalkarken kararlaştırıldı
        s.sync(plan: p, desks: desks([("a", .working(tool: nil))]), looks: [:], projectColors: [:], live: true)
        run(&s, 5)
        s.sync(plan: p, desks: desks([("a", .waiting(.question("?")))]), looks: [:], projectColors: [:], live: true)
        var cheered = false
        run(&s, 8) { if $0.instances[0].clip == .cheer { cheered = true } }
        #expect(!cheered)
    }

    /// Oda büyürken bir noktaya yürüyen köylü noktanın yeni yerine gider.
    @Test func walkingToASpotFollowsTheSpotWhenTheRoomGrows() {
        var s = sim()
        var ids = ["a", "b"]
        s.sync(plan: plan(ids), desks: desks(ids.map { ($0, AgentState.idle) }), looks: [:], projectColors: [:], live: false)
        // Biri bir noktaya doğru yürürken.
        var walking: String?
        for _ in 0..<(120 * 60) {
            s.tick(dt: 1.0 / 60)
            if s.isWalking, let id = s.reservedSpots.keys.sorted().first { walking = id; break }
        }
        guard let id = walking, let kind = s.reservedSpots[id] else { Issue.record("kimse yürümedi"); return }
        ids += ["c", "d", "e", "f", "g"]
        let bigger = plan(ids)
        s.sync(plan: bigger, desks: desks(ids.map { ($0, AgentState.idle) }), looks: [:], projectColors: [:], live: true)
        run(&s, 0.1)
        guard s.reservedSpots[id] == kind else { return }   // bu arada başka bir hedef seçtiyse geç
        run(&s, 12) { _ in }
        let room = bigger.rooms[0]
        let spot = room.spots.first { $0.kind == kind }!
        let target = room.approach(to: spot)
        if s.reservedSpots[id] == kind {
            #expect(near(s.instances.first { $0.id == id }!.position, target.seat ?? target.stand, 0.1))
        }
    }

    /// Başka odaya taşınan köylü eski noktasını bırakır, yeni odada kimseyle aynı noktayı paylaşmaz.
    @Test func movingRoomsDoesNotShareASpot() {
        var s = sim()
        func twoRooms(_ a: String) -> OfficePlan {
            let members = [OfficePlan.Member(id: "a0", roomKey: a), OfficePlan.Member(id: "b0", roomKey: "/r2")]
            return OfficePlan.make(members, slots: OfficePlan.assignSlots(members, previous: [:]))
        }
        let d = desks([("a0", .idle), ("b0", .idle)])
        s.sync(plan: twoRooms("/r1"), desks: d, looks: [:], projectColors: [:], live: false)
        run(&s, 150)
        s.sync(plan: twoRooms("/r2"), desks: d, looks: [:], projectColors: [:], live: true)
        run(&s, 60) { sim in
            let a = sim.reservedSpots["a0"], b = sim.reservedSpots["b0"]
            #expect(a == nil || a != b, "aynı oda, aynı nokta: \(String(describing: a))")
        }
    }

    /// Kalkarken gelen yeni hedef kalkışı baştan başlatmaz.
    @Test func newGoalDuringStandUpKeepsRising() {
        var s = sim()
        let p = plan(["a"])
        s.sync(plan: p, desks: desks([("a", .working(tool: nil))]), looks: [:], projectColors: [:], live: false)
        s.sync(plan: p, desks: desks([("a", .waiting(.question("?")))]), looks: [:], projectColors: [:], live: true)
        run(&s, AvatarClip.standUp.duration * 0.6)
        s.sync(plan: p, desks: desks([("a", .waiting(.permission("Bash")))]), looks: [:], projectColors: [:], live: true)
        s.sync(plan: p, desks: desks([("a", .working(tool: nil)), ], finished: []), looks: [:], projectColors: [:], live: true)
        s.sync(plan: p, desks: desks([("a", .waiting(.question("?")))]), looks: [:], projectColors: [:], live: true)
        // Kalan süre kısalmadıysa yürüyüş toplam 0,6 + 1,0 kalkış süresinden geç başlardı.
        run(&s, AvatarClip.standUp.duration * 0.5)
        #expect(s.instances[0].clip == .walk || s.isWalking)
    }

    @Test func facingAtSpotsMatchesFurniture() {
        var s = sim()
        let ids = (0..<4).map { "f\($0)" }
        let p = plan(ids)
        let room = p.rooms[0]
        s.sync(plan: p, desks: desks(ids.map { ($0, AgentState.idle) }), looks: [:], projectColors: [:], live: false)
        var checked = Set<RoomSpot.Kind>()
        run(&s, 300) { sim in
            for (id, kind) in sim.reservedSpots where !sim.isMoving {
                guard let a = sim.instances.first(where: { $0.id == id }), let spot = room.spots.first(where: { $0.kind == kind }) else { continue }
                let target = room.approach(to: spot)
                let at = target.seat ?? target.stand
                if near(a.position, at, 0.05) {
                    #expect(abs(remainder(Double(a.facing) - target.facing, 2 * .pi)) < 0.05, "\(kind)")
                    checked.insert(kind)
                }
            }
        }
        #expect(!checked.isEmpty)
    }

    /// Köylü bir eşyaya giderken ya da kullanırken eşya kapatılır: noktayı bırakır, engelin içinde kalmaz,
    /// kapalı eşyaya bir daha gitmez.
    @Test func furnitureTurnedOffWhileUsedReplans() {
        var s = sim()
        let full = plan(["a"])
        s.sync(plan: full, desks: desks([("a", .idle)]), looks: [:], projectColors: [:], live: true)
        run(&s, 3)
        let kind = try? #require(s.reservedSpots["a"])
        guard let kind else { return }
        let without = full.applying(furniture: [full.rooms[0].key: RoomFurniture.all.subtracting([RoomFurniture(rawValue: kind.rawValue)!])])
        s.sync(plan: without, desks: desks([("a", .idle)]), looks: [:], projectColors: [:], live: true)
        #expect(s.reservedSpots["a"] != kind)
        let nav = RoomNav(room: without.rooms[0])
        run(&s, 60) { sim in
            #expect(sim.reservedSpots["a"] != kind, "kapalı eşyaya gitti")
            let p = sim.instances[0].position
            let pt = PlanPoint(x: Double(p.x), z: Double(p.z))
            #expect(nav.isFree(pt) || nav.room.desks.contains { nav.room.seat(for: $0).distance(to: pt) < 0.7 }
                    || without.rooms[0].spots.contains { $0.kind == .sofa && hypot($0.x - pt.x, $0.z - pt.z) < 0.8 },
                    "engelde: \(pt)")
        }
    }

    /// Çok köylülü odada eşyalar dolunca boşta olanlar boş noktalarda bekler; hiçbiri masada uyuklamaz.
    @Test func noFreeSpotWandersToAFreePoint() {
        var s = sim()
        let ids = (0..<8).map { "v\($0)" }
        let p = plan(ids).applying(furniture: [plan(ids).rooms[0].key: [.sofa]])
        s.sync(plan: p, desks: desks(ids.map { ($0, .idle) }), looks: [:], projectColors: [:], live: false)
        run(&s, 30) { sim in
            #expect(!sim.instances.contains { $0.clip == .sitDoze }, "masada uyuklayan var")
        }
        #expect(Set(s.reservedSpots.values).count <= 1)
    }

    /// Boş noktalar oda başına bir kez (eşitlemede) hesaplanır; her karede yeniden taranmaz.
    @Test func freePointsAreScannedOncePerSync() {
        var s = sim()
        let ids = (0..<6).map { "f\($0)" }
        s.sync(plan: plan(ids), desks: desks(ids.map { ($0, .idle) }), looks: [:], projectColors: [:], live: false)
        let afterSync = s.freePointScans
        #expect(afterSync == 1)
        run(&s, 20)
        #expect(s.freePointScans == afterSync)
    }
}

