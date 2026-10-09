import Foundation
import Testing
@testable import AgentOfficeCore

/// Ofis hayatı: masalar yatay (kameraya) ya da dikey (koridora) durur, odada sekiz eşya var ve hepsi oda
/// düzenleyicisinden kapatılabilir. Yerleşim testleri iki yön için de.
@Suite struct RoomLayoutTests {
    /// İki proje: ilk oda solda, ikincisi sağda.
    func rooms(_ desks: Int, furniture: Set<RoomFurniture> = Set(RoomFurniture.allCases),
               orientation: DeskOrientation = .horizontal) -> [OfficePlan.Room] {
        let members = (0..<desks).flatMap { i in [OfficePlan.Member(id: "a\(i)", roomKey: "/a"), OfficePlan.Member(id: "b\(i)", roomKey: "/b")] }
        let plan = OfficePlan.make(members, slots: OfficePlan.assignSlots(members, previous: [:]))
            .applying(furniture: ["/a": furniture, "/b": furniture])
            .applying(deskOrientation: orientation)
        return plan.rooms
    }

    /// Varsayılan yatay: köylü masanın arkasında oturur ve kameraya bakar.
    @Test func horizontalSeatIsBehindTheDeskFacingTheCamera() {
        for room in rooms(2) {
            #expect(room.deskOrientation == .horizontal)
            for desk in room.desks {
                let seat = room.seat(for: desk)
                #expect(seat.x == desk.x && desk.z - seat.z > 0.3)
                #expect(room.seatFacing(for: desk) == OfficePlan.Room.cameraFacing)
                #expect(room.deskHalfExtents.x > room.deskHalfExtents.z)
            }
        }
    }

    @Test func verticalSeatFacesTheCorridor() {
        for room in rooms(2, orientation: .vertical) {
            for desk in room.desks {
                let seat = room.seat(for: desk)
                // Köylü masanın koridordan uzak tarafında oturur ve koridora bakar.
                #expect((seat.x - desk.x) * room.outward > 0.3, "\(room.side)")
                let facing = room.seatFacing(for: desk)
                #expect(abs(sin(facing) - (-room.outward)) < 1e-9 && abs(cos(facing)) < 1e-9, "\(room.side)")
            }
        }
    }

    func overlaps(_ a: RoomNav.Obstacle, _ b: RoomNav.Obstacle, shrink: Double) -> Bool {
        func extent(_ o: RoomNav.Obstacle) -> (Double, Double) {
            switch o.shape {
            case .rect(let hx, let hz): (hx - shrink, hz - shrink)
            case .circle(let r): (r - shrink, r - shrink)
            }
        }
        let (ax, az) = extent(a), (bx, bz) = extent(b)
        return abs(a.x - b.x) < ax + bx && abs(a.z - b.z) < az + bz
    }

    /// Eşyalar masalara, kapıya ve birbirine binmez (gövde payları çıkarılınca).
    @Test(arguments: [1, 2, 3, 5, 8], DeskOrientation.allCases)
    func desksAndFurnitureDoNotOverlap(desks: Int, orientation: DeskOrientation) {
        for room in rooms(desks, orientation: orientation) {
            let hard = RoomNav(room: room).obstacles.filter { !$0.soft }
            for (i, a) in hard.enumerated() {
                for b in hard[(i + 1)...] {
                    #expect(!overlaps(a, b, shrink: RoomNav.body), "\(room.side) \(desks): \(a) ~ \(b)")
                }
                #expect(!a.contains(room.doorInside), "kapı dolu")
            }
            for spot in room.spots { #expect(room.rect.contains(x: spot.x, z: spot.z), "\(spot.kind) oda dışında") }
        }
    }

    /// Bütün eşyalar kapalıyken de masalara ve kapıya yol var; kapalı eşya engel ve ilgi noktası değildir.
    @Test(arguments: DeskOrientation.allCases)
    func furnitureOffIsNotAnObstacleOrSpot(orientation: DeskOrientation) {
        for room in rooms(4, furniture: [], orientation: orientation) {
            #expect(room.spots.isEmpty)
            let nav = RoomNav(room: room)
            #expect(nav.obstacles.count == room.desks.count * 2)
            for desk in room.desks { #expect(nav.path(from: room.doorInside, to: room.seat(for: desk))?.last == room.seat(for: desk)) }
        }
        let some = rooms(2, furniture: [.arcade, .whiteboard])[0]
        #expect(Set(some.spots.map(\.kind)) == [.arcade, .whiteboard])
    }

    @Test(arguments: DeskOrientation.allCases)
    func everySpotIsReachableInBothSides(orientation: DeskOrientation) {
        for room in rooms(6, orientation: orientation) {
            #expect(Set(room.spots.map(\.kind)) == Set(RoomSpot.Kind.allCases))
            let nav = RoomNav(room: room)
            for spot in room.spots {
                let target = room.approach(to: spot)
                #expect(nav.isFree(target.stand), "\(room.side) \(spot.kind) yaklaşma noktası dolu")
                #expect(nav.path(from: room.doorInside, to: target.stand)?.last == target.stand, "\(room.side) \(spot.kind)")
            }
        }
    }

    /// Her masanın taburesine ve ayakta durma yerine kapıdan yol var; ayakta durma yeri boş (iki yön için).
    @Test(arguments: [1, 4, 8], DeskOrientation.allCases)
    func seatsAndStandSpotsAreReachable(desks: Int, orientation: DeskOrientation) {
        for room in rooms(desks, orientation: orientation) {
            let nav = RoomNav(room: room)
            for desk in room.desks {
                let stand = room.standSpot(for: desk), seat = room.seat(for: desk)
                #expect(nav.isFree(stand), "\(room.side) \(orientation) ayakta durma yeri dolu")
                #expect(nav.path(from: room.doorInside, to: stand)?.last == stand, "\(room.side) \(orientation)")
                #expect(nav.path(from: room.doorInside, to: seat)?.last == seat, "\(room.side) \(orientation)")
            }
        }
    }

    @Test func oldRoomStyleHasAllFurniture() throws {
        let json = Data(#"{"wallpaper":1,"floor":2,"rug":"dots"}"#.utf8)
        let style = try JSONDecoder().decode(RoomStyle.self, from: json)
        #expect(style.furniture == Set(RoomFurniture.allCases))
        #expect(RoomStyle.default(for: "/x").furniture == Set(RoomFurniture.allCases))
        var trimmed = style
        trimmed.furniture = [.sofa]
        let again = try JSONDecoder().decode(RoomStyle.self, from: JSONEncoder().encode(trimmed))
        #expect(again.furniture == [.sofa])
    }
}
