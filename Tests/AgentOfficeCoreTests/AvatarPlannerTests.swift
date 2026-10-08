import Testing
@testable import AgentOfficeCore

@Suite struct AvatarPlannerTests {
    func room(_ count: Int = 4) -> OfficePlan.Room {
        let members = (0..<count).map { OfficePlan.Member(id: "s\($0)", roomKey: "/r") }
        return OfficePlan.make(members, slots: OfficePlan.assignSlots(members, previous: [:])).rooms[0]
    }

    @Test func activityFollowsState() {
        #expect(AvatarActivity.for(state: .working(tool: "Edit")) == .typing)
        #expect(AvatarActivity.for(state: .waiting(.permission("Bash"))) == .waving)
        #expect(AvatarActivity.for(state: .idle) == .dozing)
        #expect(AvatarActivity.for(state: .starting) == .dozing)
        #expect(AvatarActivity.for(state: .exited) == .away)
        #expect(AvatarActivity.hasAvatar(kind: .claude, state: .idle))
        #expect(!AvatarActivity.hasAvatar(kind: .shell, state: .idle))
        #expect(AvatarActivity.hasAvatar(kind: .shell, state: .working(tool: "claude")))
    }

    @Test func routesAvoidDesksAndStayInside() {
        let r = room(6)
        for desk in r.desks {
            for target in [AvatarSpot.seat, .stand] {
                let path = AvatarRoute.route(from: r.doorOutside, to: target, desk: desk, room: r)
                #expect(path.first == r.doorOutside)
                #expect(path.last == (target == .seat ? r.seat(for: desk) : r.standSpot(for: desk)))
                for (a, b) in zip(path, path.dropFirst()) {
                    for i in 0...20 {
                        let t = Double(i) / 20
                        let p = PlanPoint(x: a.x + (b.x - a.x) * t, z: a.z + (b.z - a.z) * t)
                        for other in r.desks {
                            let inside = abs(p.x - other.x) < DeskGeometry.deskHalfWidth - 0.02
                                && abs(p.z - other.z) < DeskGeometry.deskHalfDepth - 0.02
                            #expect(!inside, "yol \(desk.id) → \(target) masa \(other.id) içinden geçiyor: \(p)")
                        }
                        let inRoom = r.rect.contains(x: p.x, z: p.z)
                        let inCorridor = abs(p.z - r.doorZ) < 0.01 && abs(p.x - r.doorX) <= 0.61
                        #expect(inRoom || inCorridor)
                    }
                }
            }
        }
    }

    @Test func initialLoadPlacesWithoutWalking() {
        let r = room(); let desk = r.desks[0]
        let step = AvatarPlanner.plan(current: nil, activity: .typing, desk: desk, room: r, live: false)
        #expect(step == .place(r.seat(for: desk), .sitType, facing: 0))
    }

    @Test func newSessionWalksInFromDoor() {
        let r = room(); let desk = r.desks[1]
        guard case .walk(let path, let clip, _, let hide) = AvatarPlanner.plan(current: nil, activity: .typing, desk: desk, room: r, live: true) else {
            Issue.record("yürümeliydi"); return
        }
        #expect(path.first == r.doorOutside && path.last == r.seat(for: desk) && clip == .sitType && !hide)
    }

    @Test func sameSpotOnlyChangesClip() {
        let r = room(); let desk = r.desks[0]
        let here = AvatarPose(point: r.seat(for: desk), roomKey: r.key)
        #expect(AvatarPlanner.plan(current: here, activity: .dozing, desk: desk, room: r, live: true) == .place(r.seat(for: desk), .sitDoze, facing: 0))
    }

    @Test func replanFromMidWalkStartsAtCurrentPoint() {
        let r = room(); let desk = r.desks[2]
        let mid = PlanPoint(x: r.aisleX(for: desk), z: r.z + 2.2)
        guard case .walk(let path, .wave, _, _) = AvatarPlanner.plan(current: AvatarPose(point: mid, roomKey: r.key), activity: .waving, desk: desk, room: r, live: true) else {
            Issue.record("yürümeliydi"); return
        }
        #expect(path.first == mid)
        #expect(path.last == r.standSpot(for: desk))
    }

    @Test func deskMovedFarTeleports() {
        let r = room(); let desk = r.desks[0]
        let elsewhere = AvatarPose(point: PlanPoint(x: 40, z: 40), roomKey: "/other")
        #expect(AvatarPlanner.plan(current: elsewhere, activity: .typing, desk: desk, room: r, live: true) == .place(r.seat(for: desk), .sitType, facing: 0))
    }

    @Test func exitedWalksOutAndHides() {
        let r = room(); let desk = r.desks[0]
        let seated = AvatarPose(point: r.seat(for: desk), roomKey: r.key)
        guard case .walk(let path, _, _, let hide) = AvatarPlanner.plan(current: seated, activity: .away, desk: desk, room: r, live: true) else {
            Issue.record("yürümeliydi"); return
        }
        #expect(path.last == r.doorOutside && hide)
        #expect(AvatarPlanner.plan(current: nil, activity: .away, desk: desk, room: r, live: false) == .hide)
    }

    @Test func everyRouteBetweenSpotsAvoidsDesks() {
        let r = room(6)
        for desk in r.desks {
            let starts = [r.seat(for: desk), r.standSpot(for: desk), r.doorOutside, PlanPoint(x: r.aisleX(for: desk), z: r.doorZ)]
            for start in starts {
                for target in [AvatarSpot.seat, .stand, .outside] {
                    let path = AvatarRoute.route(from: start, to: target, desk: desk, room: r)
                    #expect(path.first == start)
                    #expect(path.last == AvatarRoute.point(target, desk: desk, room: r))
                    #expect(clear(path, r), "\(start) → \(target)")
                }
            }
        }
    }

    func clear(_ path: [PlanPoint], _ r: OfficePlan.Room) -> Bool {
        for (a, b) in zip(path, path.dropFirst()) {
            for i in 0...40 {
                let t = Double(i) / 40
                let p = PlanPoint(x: a.x + (b.x - a.x) * t, z: a.z + (b.z - a.z) * t)
                for other in r.desks where abs(p.x - other.x) < DeskGeometry.deskHalfWidth - 0.02
                    && abs(p.z - other.z) < DeskGeometry.deskHalfDepth - 0.02 { return false }
            }
        }
        return true
    }

    @Test func clipFramesMatchArtTimeline() {
        #expect(AvatarClip.walk.frames == 31...54)
        #expect(AvatarClip.wave.frames == 141...164)
    }

    @Test func roomShiftedOnSameSideTeleports() {
        let r = room(4)
        var shifted = r
        shifted.z += 1  // önündeki oda büyüdü: aynı tarafta bir karo kaydı
        let desk = shifted.desks.isEmpty ? r.desks[0] : r.desks[0]
        let movedDesk = OfficePlan.Desk(id: desk.id, x: desk.x, z: desk.z + 1)
        let waving = AvatarPose(point: r.standSpot(for: desk), roomKey: r.key, room: r.rect)
        #expect(AvatarPlanner.plan(current: waving, activity: .waving, desk: movedDesk, room: shifted, live: true)
                == .place(shifted.standSpot(for: movedDesk), .wave, facing: 0))
    }

    @Test func standSpotsAreUniquePerDesk() {
        let r = room(6)
        let spots = r.desks.map { r.standSpot(for: $0) }
        for (i, a) in spots.enumerated() {
            for b in spots.dropFirst(i + 1) {
                #expect(a.distance(to: b) > 0.25, "\(a) ve \(b) çakışıyor")
            }
        }
    }
}
