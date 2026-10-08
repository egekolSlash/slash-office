import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct AvatarBehaviorTests {
    let allSpots = RoomSpot.Kind.allCases
    let points = [PlanPoint(x: 1, z: 2), PlanPoint(x: 2, z: 5), PlanPoint(x: 3, z: 6)]

    /// `seconds` boyunca 0,1 sn adımlarla ilerletir; verilen kararları toplar. `arrive`: sim gibi her hedefe
    /// hemen varıldığını bildirir (noktadaki kalma süresi varınca başlar).
    func run(_ b: inout AvatarBehavior, seconds: Double, spots: [RoomSpot.Kind]? = nil, freePoints: [PlanPoint] = [],
             step: Double = 0.1, arrive: Bool = false) -> [AvatarBehavior.Decision] {
        var out: [AvatarBehavior.Decision] = []
        var t = 0.0
        while t < seconds {
            if let d = b.advance(dt: step, freeSpots: spots ?? allSpots, freePoints: freePoints) {
                out.append(d)
                if arrive, case .goal = d { b.arrived() }
            }
            t += step
        }
        return out
    }

    func goals(_ ds: [AvatarBehavior.Decision]) -> [AvatarGoal] {
        ds.compactMap { if case .goal(let g) = $0 { g } else { nil } }
    }

    func oneShots(_ ds: [AvatarBehavior.Decision]) -> [AvatarClip] {
        ds.compactMap { if case .oneShot(let c) = $0 { c } else { nil } }
    }

    @Test func workingStaysSeatedWithOccasionalVariations() {
        var b = AvatarBehavior(id: "w")
        b.setActivity(.typing, finishedNow: false)
        let ds = run(&b, seconds: 120)
        #expect(ds.first == .goal(.seat(loop: .sitType)))
        #expect(!ds.dropFirst().contains { if case .goal = $0 { true } else { false } })   // masada kalır
        let shots = oneShots(ds)
        #expect(shots.count >= 4 && shots.count <= 16)                                       // 8–20 sn'de bir
        #expect(Set(shots).isSubset(of: [.sitSip, .sitThink, .sitStretch, .sitDraw, .sitWrite, .sitRead]))
    }

    /// Masa başında yeni hareketler de oynar: çizme, yazma, kâğıt okuma.
    @Test func workingUsesNewDeskClips() {
        var b = AvatarBehavior(id: "desk")
        b.setActivity(.typing, finishedNow: false)
        let shots = Set(oneShots(run(&b, seconds: 900)))
        #expect(!shots.isDisjoint(with: [.sitDraw, .sitWrite, .sitRead]))
    }

    @Test func waitingWavesAndFidgets() {
        var b = AvatarBehavior(id: "q")
        b.setActivity(.waving, finishedNow: false)
        let ds = run(&b, seconds: 40)
        #expect(ds.first == .goal(.stand(loop: .wave)))
        let shots = oneShots(ds)
        #expect(!shots.isEmpty && Set(shots).isSubset(of: [.waitTap, .lookAround]))
    }

    /// Boştaki köylü masada oturup beklemez: hemen bir eşyaya gider, hiçbir zaman masaya dönmez.
    @Test func idleNeverSitsAtTheDesk() {
        var b = AvatarBehavior(id: "i")
        b.setActivity(.dozing, finishedNow: false)
        let gs = goals(run(&b, seconds: 900, freePoints: points, arrive: true))
        if case .spot? = gs.first {} else { Issue.record("ilk hedef bir eşya değil: \(String(describing: gs.first))") }
        #expect(gs.count > 10)
        #expect(!gs.contains { if case .seat = $0 { true } else { false } })
    }

    /// Eşyalar arasında dolaşır, son iki eşyayı tekrar seçmez.
    @Test func idleCyclesSpotsWithoutRepeatingTheLastTwo() {
        var b = AvatarBehavior(id: "cycle")
        b.setActivity(.dozing, finishedNow: false)
        let kinds = goals(run(&b, seconds: 1200, arrive: true)).compactMap { g -> RoomSpot.Kind? in
            if case .spot(let k, _, _, _) = g { k } else { nil }
        }
        #expect(kinds.count > 15)
        #expect(Set(kinds).count >= 6)
        for i in 2..<kinds.count { #expect(kinds[i] != kinds[i - 1] && kinds[i] != kinds[i - 2], "\(kinds)") }
    }

    @Test func spotGoalsUseTheRightClips() {
        let expected: [RoomSpot.Kind: AvatarGoal] = [
            .sofa: .spot(.sofa, loop: .sofaSit, oneShot: nil, dwell: 0),
            .plant: .spot(.plant, loop: .lookAround, oneShot: .inspect, dwell: 0),
            .waterCooler: .spot(.waterCooler, loop: .idle, oneShot: .drink, dwell: 0),
            .coffeeTable: .spot(.coffeeTable, loop: .idle, oneShot: .stretch, dwell: 0),
            .bookshelf: .spot(.bookshelf, loop: .readBook, oneShot: nil, dwell: 0),
            .arcade: .spot(.arcade, loop: .playArcade, oneShot: nil, dwell: 0),
            .whiteboard: .spot(.whiteboard, loop: .drawBoard, oneShot: nil, dwell: 0),
            .coffeeMachine: .spot(.coffeeMachine, loop: .idle, oneShot: .brewCoffee, dwell: 0),
        ]
        for (kind, goal) in expected {
            var b = AvatarBehavior(id: "s-\(kind)")
            b.setActivity(.dozing, finishedNow: false)
            let first = goals(run(&b, seconds: 5, spots: [kind])).first
            #expect(first?.withoutDwell == goal, "\(kind)")
        }
    }

    /// Eşyada kalırken ara hareketler: arcade'de sevinç, tahtada geri çekilip bakma, kahveden sonra içme.
    @Test func furnitureExtraMoves() {
        for (kind, clip) in [(RoomSpot.Kind.arcade, AvatarClip.cheer), (.whiteboard, .stepBackLook), (.coffeeMachine, .drink)] {
            var b = AvatarBehavior(id: "x-\(kind)")
            b.setActivity(.dozing, finishedNow: false)
            _ = run(&b, seconds: 1, spots: [kind])
            b.arrived()
            #expect(oneShots(run(&b, seconds: 12, spots: [kind])).contains(clip), "\(kind)")
        }
    }

    /// Bütün eşyalar doluysa odada boş bir noktaya gider ve orada etrafına bakar ya da gerinir.
    @Test func noFreeSpotWandersToAFreePoint() {
        var b = AvatarBehavior(id: "n")
        b.setActivity(.dozing, finishedNow: false)
        let gs = goals(run(&b, seconds: 120, spots: [], freePoints: points, arrive: true))
        #expect(gs.count >= 5)
        for g in gs {
            guard case .point(let p, let loop, let dwell) = g else { Issue.record("beklenmeyen hedef \(g)"); continue }
            #expect(points.contains(p))
            #expect([AvatarClip.lookAround, .stretch, .idle].contains(loop))
            #expect((6...12).contains(dwell))
        }
    }

    /// Ne eşya ne boş nokta: masanın yanında ayakta bekler (oturmaz).
    @Test func noSpotNorPointStandsByTheDesk() {
        var b = AvatarBehavior(id: "np")
        b.setActivity(.dozing, finishedNow: false)
        let gs = goals(run(&b, seconds: 60, spots: [], arrive: true))
        #expect(!gs.isEmpty && gs.allSatisfy { if case .stand = $0 { true } else { false } })
    }

    @Test func cheerOncePerFinish() {
        var b = AvatarBehavior(id: "c")
        b.setActivity(.typing, finishedNow: false)
        _ = run(&b, seconds: 3)
        b.setActivity(.dozing, finishedNow: true)
        let ds = run(&b, seconds: 10)
        #expect(ds.first == .goal(.stand(loop: .idle)))
        #expect(oneShots(ds).filter { $0 == .cheer }.count == 1)
        // Aynı durum yeniden bildirilince tekrar sevinmez; yeni bir bitiş yeniden sevindirir.
        b.setActivity(.dozing, finishedNow: false)
        #expect(oneShots(run(&b, seconds: 10)).filter { $0 == .cheer }.isEmpty)
        b.setActivity(.typing, finishedNow: false)
        _ = run(&b, seconds: 2)
        b.setActivity(.dozing, finishedNow: true)
        #expect(oneShots(run(&b, seconds: 10)).filter { $0 == .cheer }.count == 1)
    }

    /// Sevinçten sonra boşta kuralları: masaya dönmez, eşyaya ya da boş bir noktaya gider.
    @Test func finishedCheersOnceThenIdles() {
        var b = AvatarBehavior(id: "nc")
        b.setActivity(.typing, finishedNow: false)
        _ = run(&b, seconds: 1, spots: [])
        b.setActivity(.dozing, finishedNow: true)
        let gs = goals(run(&b, seconds: 60, freePoints: points, arrive: true))
        #expect(gs.first == .stand(loop: .idle))
        #expect(gs.dropFirst().allSatisfy { if case .seat = $0 { false } else { true } })
        if case .spot? = gs.dropFirst().first {} else { Issue.record("sevinçten sonra eşyaya gitmedi: \(gs)") }
    }

    /// Noktadaki kalma süresi köylü varınca başlar (uzun yürüyüş süreyi yemez).
    @Test func dwellStartsOnArrival() {
        var b = AvatarBehavior(id: "dw")
        b.setActivity(.dozing, finishedNow: false)
        var goal: AvatarGoal?
        for _ in 0..<2000 {
            if case .goal(let g)? = b.advance(dt: 0.1, freeSpots: [.waterCooler]), case .spot = g { goal = g; break }
        }
        guard case .spot(_, _, _, let dwell)? = goal else { Issue.record("noktaya gitmedi"); return }
        // Varmadan (ör. 40 sn yürüyüş) karar yok.
        #expect(run(&b, seconds: 40, spots: [.waterCooler]).isEmpty)
        b.arrived()
        #expect(run(&b, seconds: dwell * 0.9, spots: [.waterCooler]).isEmpty)
        #expect(!run(&b, seconds: dwell * 0.2 + 0.2, spots: [.waterCooler]).isEmpty)
    }

    @Test func awayLeaves() {
        var b = AvatarBehavior(id: "a")
        b.setActivity(.away, finishedNow: false)
        #expect(run(&b, seconds: 1) == [.goal(.leave)])
    }

    @Test func sameIdSameSequence() {
        var a = AvatarBehavior(id: "x"), b = AvatarBehavior(id: "x"), c = AvatarBehavior(id: "y")
        a.setActivity(.typing, finishedNow: false); b.setActivity(.typing, finishedNow: false); c.setActivity(.typing, finishedNow: false)
        let ra = run(&a, seconds: 100), rb = run(&b, seconds: 100), rc = run(&c, seconds: 100)
        #expect(ra == rb)
        #expect(ra != rc)
    }

    @Test func timersAdvanceWithLargeSteps() {
        var b = AvatarBehavior(id: "l")
        b.setActivity(.typing, finishedNow: false)
        let ds = run(&b, seconds: 1000, step: 30)
        #expect(oneShots(ds).count >= 10)
    }
}

extension AvatarGoal {
    /// Testlerde süreyi yok saymak için.
    var withoutDwell: AvatarGoal {
        if case .spot(let k, let l, let o, _) = self { return .spot(k, loop: l, oneShot: o, dwell: 0) }
        return self
    }
}
