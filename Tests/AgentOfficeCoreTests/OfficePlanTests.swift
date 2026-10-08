import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct OfficePlanTests {
    func members(_ pairs: [(String, String)]) -> [OfficePlan.Member] {
        pairs.map { OfficePlan.Member(id: $0.0, roomKey: $0.1) }
    }

    func plan(_ pairs: [(String, String)]) -> OfficePlan {
        let list = members(pairs)
        return OfficePlan.make(list, slots: OfficePlan.assignSlots(list, previous: [:]))
    }

    func overlaps(_ a: PlanRect, _ b: PlanRect) -> Bool {
        a.minX < b.maxX - 1e-9 && b.minX < a.maxX - 1e-9 && a.minZ < b.maxZ - 1e-9 && b.minZ < a.maxZ - 1e-9
    }

    @Test func roomsGrowSidewaysWithFixedDepth() {
        let rooms = [1, 2, 3, 4, 5, 8].map { n in plan((0..<n).map { ("s\($0)", "/a") }).rooms[0] }
        #expect(rooms.allSatisfy { $0.depth == OfficePlan.roomDepth })
        #expect(zip(rooms.map(\.width), [4.8, 4.8, 4.8, 4.8, 6.7, 8.6]).allSatisfy { abs($0 - $1) < 1e-9 })
        // Sol oda koridora dayanır, sola (dışa) büyür.
        #expect(rooms.allSatisfy { abs($0.x + $0.width - OfficePlan.corridorX) < 1e-9 })
    }

    @Test func rightRoomsStartAtCorridorAndGrowRight() {
        let p = plan([("a", "/a"), ("b", "/b"), ("c", "/b"), ("d", "/b")])
        let right = p.rooms[1]
        #expect(right.side == .right && right.x == OfficePlan.corridorX + OfficePlan.corridorWidth)
        #expect(right.outward == 1 && p.rooms[0].outward == -1)
        #expect(right.corridorEdgeX == right.x && p.rooms[0].corridorEdgeX == OfficePlan.corridorX)
    }

    @Test func growingRoomKeepsDeskPositions() {
        let small = plan([("a", "/r"), ("b", "/r")])
        let big = plan([("a", "/r"), ("b", "/r"), ("c", "/r"), ("d", "/r"), ("e", "/r")])
        for id in ["a", "b"] {
            #expect(small.rooms[0].desks.first { $0.id == id } == big.rooms[0].desks.first { $0.id == id })
        }
    }

    @Test func desksSitInTwoRowsInsideTheRoom() {
        let room = plan((0..<7).map { ("s\($0)", "/a") }).rooms[0]
        #expect(Set(room.desks.map { (($0.z - room.z) * 100).rounded() / 100 }) == [OfficePlan.backRowZ, OfficePlan.frontRowZ])
        for desk in room.desks { #expect(room.rect.contains(x: desk.x, z: desk.z)) }
        #expect(Set(room.desks.map { "\($0.x),\($0.z)" }).count == 7)
        // Aynı sıradaki komşu masalar 1,6 m arayla.
        let back = room.desks.filter { $0.z - room.z < 2 }.map(\.x).sorted()
        for (a, b) in zip(back, back.dropFirst()) { #expect(abs(b - a - OfficePlan.columnSpacing) < 1e-9) }
    }

    @Test func roomsOnTheSameSideStackWithoutOverlap() {
        let p = plan([("1", "/a"), ("2", "/b"), ("3", "/c"), ("4", "/c"), ("5", "/d"), ("6", "/e")])
        #expect(p.rooms.map(\.side) == [.left, .right, .left, .right, .left])
        #expect(p.rooms[2].z == p.rooms[0].z + OfficePlan.roomDepth)
        for (i, a) in p.rooms.enumerated() {
            for b in p.rooms.dropFirst(i + 1) { #expect(!overlaps(a.rect, b.rect), "\(a.key) \(b.key)") }
        }
        #expect(!p.rooms.contains { overlaps($0.rect, p.corridor) })
        #expect(p.corridor.maxX - p.corridor.minX == OfficePlan.corridorWidth)
    }

    @Test func lotsAreWhereTheNextRoomsGoAndDoNotOverlap() {
        let p = plan([("a", "/a"), ("b", "/b"), ("c", "/c")])
        #expect(p.lots.count == 2)
        for lot in p.lots { for room in p.rooms { #expect(!overlaps(lot, room.rect)) } }
        let grown = plan([("a", "/a"), ("b", "/b"), ("c", "/c"), ("d", "/d")])
        let newRoom = grown.rooms[3]
        #expect(p.lots.contains { abs($0.minX - newRoom.rect.minX) < 1e-9 && abs($0.minZ - newRoom.rect.minZ) < 1e-9 })
        #expect(p.lot(atX: p.lots[0].minX + 0.5, z: p.lots[0].minZ + 0.5) == 0)
        #expect(p.lot(atX: OfficePlan.corridorX + 1, z: 0.5) == nil)
    }

    @Test func emptyPlanHasLotsOnBothSides() {
        let p = plan([])
        #expect(p.rooms.isEmpty && p.bounds.isEmpty)
        #expect(p.lots.count == 2)
        #expect(p.lots[0].maxX <= OfficePlan.corridorX && p.lots[1].minX >= OfficePlan.corridorX + OfficePlan.corridorWidth)
    }

    @Test func spotsAreInTheLoungeStripAwayFromDoorAndEachOther() {
        for n in [1, 3, 6] {
            for room in plan((0..<n).map { ("s\($0)", "/a") } + [("x", "/b")]).rooms {
                #expect(Set(room.spots.map(\.kind)) == Set(RoomSpot.Kind.allCases))
                for spot in room.spots {
                    #expect(room.rect.contains(x: spot.x, z: spot.z))
                    // Tahta ve kitaplık arka tarafta (masa sütunları arası, dış köşe); diğerleri ön şeritte.
                    if spot.kind != .whiteboard && spot.kind != .bookshelf { #expect(spot.z - room.z > OfficePlan.frontRowZ + 0.5) }
                    #expect(hypot(spot.x - room.doorInside.x, spot.z - room.doorInside.z) > 0.6)
                }
                for (i, a) in room.spots.enumerated() {
                    for b in room.spots.dropFirst(i + 1) { #expect(hypot(a.x - b.x, a.z - b.z) > 0.6) }
                }
            }
        }
    }

    @Test func onlyTheFirstRoomPerSideHasATallBackWall() {
        let p = plan([("1", "/a"), ("2", "/b"), ("3", "/c")])
        #expect(p.rooms[0].backWallHeight == OfficePlan.wallHeight)
        #expect(p.rooms[1].backWallHeight == OfficePlan.wallHeight)
        #expect(p.rooms[2].backWallHeight == OfficePlan.lowWallHeight)
    }

    @Test func removedSlotIsReusedOthersStay() {
        let first = members([("a", "/r"), ("b", "/r"), ("c", "/r")])
        let slots = OfficePlan.assignSlots(first, previous: [:])
        #expect(slots.mapValues(\.index) == ["a": 0, "b": 1, "c": 2])
        let second = members([("a", "/r"), ("c", "/r"), ("d", "/r")])
        let next = OfficePlan.assignSlots(second, previous: slots)
        #expect(next.mapValues(\.index) == ["a": 0, "c": 2, "d": 1])
        let before = OfficePlan.make(first, slots: slots).rooms[0].desks.first { $0.id == "c" }
        let after = OfficePlan.make(second, slots: next).rooms[0].desks.first { $0.id == "c" }
        #expect(before == after)
    }

    @Test func sessionMovingRoomsGetsSlotInNewRoom() {
        let slots = OfficePlan.assignSlots(members([("a", "/r"), ("b", "/s")]), previous: [:])
        let moved = OfficePlan.assignSlots(members([("a", "/s"), ("b", "/s")]), previous: slots)
        #expect(moved["b"] == OfficePlan.DeskSlot(roomKey: "/s", index: 0))
        #expect(moved["a"] == OfficePlan.DeskSlot(roomKey: "/s", index: 1))
    }

    @Test func hitTestingFindsDeskAndRoom() {
        let p = plan([("a", "/a"), ("b", "/b")])
        let desk = p.rooms[1].desks[0]
        #expect(p.desk(atX: desk.x + 0.2, z: desk.z - 0.2) == "b")
        #expect(p.desk(atX: OfficePlan.corridorX + 0.7, z: 1.3) == nil)
        #expect(p.room(atX: p.rooms[0].x + 0.1, z: p.rooms[0].z + 0.1)?.key == "/a")
        #expect(p.room(atX: OfficePlan.corridorX + 0.7, z: 0.5) == nil)
    }

    @Test func emptyPlan() {
        let p = plan([])
        #expect(p.rooms.isEmpty)
        #expect(p.bounds.isEmpty)
    }

    @Test func titleAndDoorFaceCorridor() {
        let p = plan([("1", "/git/juice-merge"), ("2", "/git/room-logic")])
        #expect(p.rooms[0].title == "juice-merge")
        #expect(p.rooms[0].doorX == OfficePlan.corridorX)
        #expect(p.rooms[1].doorX == OfficePlan.corridorX + OfficePlan.corridorWidth)
        #expect(p.rooms[0].doorZ == p.rooms[0].z + OfficePlan.walkwayZ)
        #expect(p.rooms[0].doorInside.x < p.rooms[0].doorX && p.rooms[0].doorOutside.x > p.rooms[0].doorX)
    }

    @Test func closingFirstSessionKeepsRoomOrder() {
        let first = members([("A1", "/a"), ("B1", "/b"), ("A2", "/a")])
        let order = OfficePlan.roomOrder(first, previous: [])
        #expect(order == ["/a", "/b"])
        let second = members([("B1", "/b"), ("A2", "/a")])
        let next = OfficePlan.roomOrder(second, previous: order)
        #expect(next == ["/a", "/b"])
        let plan = OfficePlan.make(second, slots: OfficePlan.assignSlots(second, previous: [:]), order: next)
        #expect(plan.rooms.map(\.key) == ["/a", "/b"])
        #expect(plan.rooms.map(\.side) == [.left, .right])
        // Odası boşalan proje kalkar, yeni proje sona eklenir.
        let third = members([("A2", "/a"), ("C1", "/c")])
        #expect(OfficePlan.roomOrder(third, previous: next) == ["/a", "/c"])
    }
}
