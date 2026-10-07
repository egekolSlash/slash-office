import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct RoomNavTests {
    func room(_ desks: Int) -> OfficePlan.Room {
        let members = (0..<desks).map { OfficePlan.Member(id: "d\($0)", roomKey: "/r") }
        return OfficePlan.make(members, slots: OfficePlan.assignSlots(members, previous: [:])).rooms[0]
    }

    func length(_ path: [PlanPoint]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    func clear(_ path: [PlanPoint], _ nav: RoomNav, _ room: OfficePlan.Room) -> Bool {
        for (a, b) in zip(path, path.dropFirst()) {
            for i in 0...20 {
                let t = Double(i) / 20
                let p = PlanPoint(x: a.x + (b.x - a.x) * t, z: a.z + (b.z - a.z) * t)
                // Uçlardaki 0,35 m (kendi taburesi, kapı) serbest; arası boş olmalı.
                if p.distance(to: path.first!) < 0.36 || p.distance(to: path.last!) < 0.36 { continue }
                if !nav.isFree(p) || !room.rect.contains(x: p.x, z: p.z) { return false }
            }
        }
        return true
    }

    /// Köylülerin gerçekten gittiği noktalar arasındaki her yol engelsiz ve oda içinde
    /// (rastgele noktalar koltuk-sehpa-duvar arasındaki kapalı ceplere düşebilir; oralara yol olmaması doğru).
    @Test(arguments: [1, 4, 7])
    func pathAvoidsObstaclesAndStaysInside(desks: Int) {
        let r = room(desks)
        let nav = RoomNav(room: r)
        let points = r.desks.flatMap { [r.seat(for: $0), r.standSpot(for: $0)] } + r.spots.map { r.approach(to: $0).stand }
            + [r.doorInside]
        for a in points {
            for b in points where a != b {
                let path = nav.path(from: a, to: b)
                #expect(path?.last == b, "\(a) → \(b)")
                if let path { #expect(clear(path, nav, r), "\(a) → \(b): \(path)") }
            }
        }
    }

    @Test func pathReachesSeatsSpotsAndDoor() {
        let r = room(6)
        let nav = RoomNav(room: r)
        let door = r.doorInside
        for desk in r.desks {
            let path = nav.path(from: door, to: r.seat(for: desk))
            #expect(path?.last == r.seat(for: desk), "\(desk.id)")
            if let path { #expect(clear(path, nav, r)) }
        }
        for spot in r.spots {
            let target = r.approach(to: spot)
            #expect(nav.isFree(target.stand), "\(spot.kind) yaklaşma noktası dolu")
            let path = nav.path(from: r.seat(for: r.desks[0]), to: target.stand)
            #expect(path?.last == target.stand, "\(spot.kind)")
        }
        #expect(nav.path(from: r.seat(for: r.desks[5]), to: door)?.last == door)
    }

    @Test func blockedTargetFallsBackToNearestFree() {
        let r = room(2)
        let nav = RoomNav(room: r)
        let insideDesk = PlanPoint(x: r.desks[0].x, z: r.desks[0].z)
        #expect(!nav.isFree(insideDesk))
        let path = nav.path(from: r.doorInside, to: insideDesk)
        #expect(path != nil)
        if let last = path?.last { #expect(last.distance(to: insideDesk) < 0.9) }
    }

    @Test func pathIsShortAfterSmoothing() {
        let r = room(2)
        let nav = RoomNav(room: r)
        // Dinlenme şeridinde engelsiz iki nokta: neredeyse düz çizgi.
        let a = PlanPoint(x: r.corridorEdgeX + r.outward * 0.9, z: r.z + 4.4)
        let b = PlanPoint(x: r.corridorEdgeX + r.outward * 2.6, z: r.z + 4.2)
        let path = nav.path(from: a, to: b)!
        #expect(length(path) < a.distance(to: b) * 1.1)
        // Masa arkasından kapıya: düz çizginin 1,6 katını geçmez.
        let seat = r.seat(for: r.desks[0])
        let toDoor = nav.path(from: seat, to: r.doorInside)!
        #expect(length(toDoor) < seat.distance(to: r.doorInside) * 1.6)
    }

    @Test func approachFacesTheFurniture() {
        let r = room(3)
        for spot in r.spots {
            let a = r.approach(to: spot)
            let toward = atan2(spot.x - a.stand.x, spot.z - a.stand.z)
            if spot.kind == .sofa {
                #expect(a.seat != nil && abs(a.facing - spot.facing) < 1e-9)
            } else {
                #expect(abs(remainder(a.facing - toward, 2 * .pi)) < 0.01, "\(spot.kind)")
                #expect(a.seat == nil)
            }
        }
    }
}
