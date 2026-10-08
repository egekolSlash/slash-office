import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct AvatarBehaviorTests {
    let allSpots: [RoomSpot.Kind] = [.sofa, .coffeeTable, .waterCooler, .plant]

    /// `seconds` boyunca 0,1 sn adımlarla ilerletir; verilen kararları toplar.
    func run(_ b: inout AvatarBehavior, seconds: Double, spots: [RoomSpot.Kind]? = nil, step: Double = 0.1) -> [AvatarBehavior.Decision] {
        var out: [AvatarBehavior.Decision] = []
        var t = 0.0
        while t < seconds {
            if let d = b.advance(dt: step, freeSpots: spots ?? allSpots) { out.append(d) }
            t += step
        }
        return out
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
        #expect(Set(shots).isSubset(of: [.sitSip, .sitThink, .sitStretch]))
    }

    @Test func waitingWavesAndFidgets() {
        var b = AvatarBehavior(id: "q")
        b.setActivity(.waving, finishedNow: false)
        let ds = run(&b, seconds: 40)
        #expect(ds.first == .goal(.stand(loop: .wave)))
        let shots = oneShots(ds)
        #expect(!shots.isEmpty && Set(shots).isSubset(of: [.waitTap, .lookAround]))
    }

    @Test func idleDozesThenWandersToAFreeSpot() {
        var b = AvatarBehavior(id: "i")
        b.setActivity(.dozing, finishedNow: false)
        let ds = run(&b, seconds: 200)
        #expect(ds.first == .goal(.seat(loop: .sitDoze)))
        let spotGoals = ds.compactMap { d -> RoomSpot.Kind? in
            if case .goal(.spot(let kind, _, _, _)) = d { kind } else { nil }
        }
        #expect(!spotGoals.isEmpty)
        // İlk dolaşma 20–60 sn uyukladıktan sonra.
        var b2 = AvatarBehavior(id: "i")
        b2.setActivity(.dozing, finishedNow: false)
        _ = b2.advance(dt: 0.1, freeSpots: allSpots)
        #expect(run(&b2, seconds: 19).allSatisfy { if case .goal(.spot) = $0 { false } else { true } })
    }

    @Test func spotGoalsUseTheRightClips() {
        for (kind, check) in [(RoomSpot.Kind.sofa, { (g: AvatarGoal) in g == .spot(.sofa, loop: .sofaSit, oneShot: nil, dwell: 0) }),
                              (.plant, { $0 == .spot(.plant, loop: .lookAround, oneShot: .inspect, dwell: 0) }),
                              (.waterCooler, { $0 == .spot(.waterCooler, loop: .idle, oneShot: .drink, dwell: 0) }),
                              (.coffeeTable, { $0 == .spot(.coffeeTable, loop: .idle, oneShot: .stretch, dwell: 0) })] {
            var b = AvatarBehavior(id: "s-\(kind)")
            b.setActivity(.dozing, finishedNow: false)
            let goal = run(&b, seconds: 120, spots: [kind]).compactMap { d -> AvatarGoal? in
                if case .goal(let g) = d, case .spot = g { g } else { nil }
            }.first
            #expect(goal.map { check($0.withoutDwell) } == true, "\(kind)")
        }
    }

    @Test func noFreeSpotStaysAtDesk() {
        var b = AvatarBehavior(id: "n")
        b.setActivity(.dozing, finishedNow: false)
        let ds = run(&b, seconds: 300, spots: [])
        #expect(ds == [.goal(.seat(loop: .sitDoze))])
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

    /// Boş nokta yokken sevinçten sonra ayakta kalmaz, masasına dönüp uyur.
    @Test func afterCheerWithNoFreeSpotGoesBackToTheDesk() {
        var b = AvatarBehavior(id: "nc")
        b.setActivity(.typing, finishedNow: false)
        _ = run(&b, seconds: 1, spots: [])
        b.setActivity(.dozing, finishedNow: true)
        // Sim her hedefe varışı bildirir (sevinç süresi varınca başlar).
        var goals: [AvatarGoal] = []
        for _ in 0..<1200 {
            if case .goal(let g)? = b.advance(dt: 0.1, freeSpots: []) { goals.append(g); b.arrived() }
        }
        #expect(goals.first == .stand(loop: .idle))
        #expect(goals.last == .seat(loop: .sitDoze))
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
