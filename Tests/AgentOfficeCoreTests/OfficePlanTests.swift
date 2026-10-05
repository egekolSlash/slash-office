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

    @Test func roomSizeGrowsWithDeskCount() {
        let sizes = [1, 2, 3, 4, 5, 6, 9].map { count -> (Int, Int) in
            let room = plan((0..<count).map { ("s\($0)", "/a") }).rooms[0]
            return (room.width, room.depth)
        }
        #expect(sizes.map(\.0) == [2, 2, 3, 3, 3, 3, 3])
        #expect(sizes.map(\.1) == [2, 2, 2, 2, 3, 3, 3])
    }

    @Test func roomsAlternateSidesInFirstSeenOrder() {
        let p = plan([("1", "/a"), ("2", "/b"), ("3", "/a"), ("4", "/c")])
        #expect(p.rooms.map(\.key) == ["/a", "/b", "/c"])
        #expect(p.rooms.map(\.side) == [.left, .right, .left])
        // Sol odalar koridora (x = 3) dayanır, sağdakiler koridordan (x = 4.5) başlar.
        #expect(p.rooms[0].x + Double(p.rooms[0].width) == OfficePlan.corridorX)
        #expect(p.rooms[1].x == OfficePlan.corridorX + OfficePlan.corridorWidth)
        // Aynı taraftaki odalar arka arkaya dizilir.
        #expect(p.rooms[2].z == p.rooms[0].z + Double(p.rooms[0].depth))
        #expect(p.corridor.maxZ == p.rooms[2].z + Double(p.rooms[2].depth))
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

    @Test func crowdedRoomKeepsDesksInsideAndApart() {
        let room = plan((0..<10).map { ("s\($0)", "/a") }).rooms[0]
        #expect(room.desks.count == 10)
        for desk in room.desks {
            #expect(desk.x > room.x && desk.x < room.x + Double(room.width))
            #expect(desk.z > room.z && desk.z < room.z + Double(room.depth))
        }
        let positions = Set(room.desks.map { "\($0.x),\($0.z)" })
        #expect(positions.count == 10)
    }

    @Test func hitTestingFindsDeskAndRoom() {
        let p = plan([("a", "/a"), ("b", "/b")])
        let desk = p.rooms[1].desks[0]
        #expect(p.desk(atX: desk.x + 0.2, z: desk.z - 0.2) == "b")
        #expect(p.desk(atX: OfficePlan.corridorX + 0.7, z: 0.1) == nil)
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

    @Test func roomInFrontDrawsAboveRoomBehindAndOnlyOuterWallsAreTall() {
        let p = plan([("1", "/a"), ("2", "/b"), ("3", "/c"), ("4", "/c")])
        let back = p.rooms[0], front = p.rooms[2]
        #expect(front.side == back.side && front.z > back.z)
        // Öndeki odanın en arka masası, arkadaki odanın ön duvarının üstüne çizilir.
        let frontDesk = front.desks.min { $0.x + $0.z < $1.x + $1.z }!
        #expect(OfficeDepth.desk(frontDesk, in: front) > OfficeDepth.frontWalls(back))
        #expect(OfficeDepth.floor(front) > OfficeDepth.frontWalls(back))
        // Tam boy duvar sadece binanın dış arka kenarlarında: arkadaki odayı örtmesin.
        #expect(back.backWallHeights == (z: OfficePlan.wallHeight, x: OfficePlan.wallHeight))
        #expect(front.backWallHeights.z == OfficePlan.lowWallHeight)
        #expect(front.backWallHeights.x == OfficePlan.wallHeight)
        #expect(p.rooms[1].backWallHeights.x == OfficePlan.lowWallHeight)
    }
}
