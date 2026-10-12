import Foundation
import Testing
@testable import AgentOfficeCore

/// Oda dekoru: yuvalar odanın içinde ve öteki eşyalarla çakışmıyor; her yuvaya her uyan eşya konunca bütün masalara,
/// taburelere ve eşya noktalarına hâlâ yürünebiliyor; seçimler kaydedilip geri geliyor.
@Suite struct RoomDecorTests {
    /// İki oda (her taraftan biri: ikisinin de arka duvarı tam boy) + öndeki iki oda (alçak arka duvar).
    static func plan(desks: Int, orientation: DeskOrientation, decor: [String: RoomDecor?] = [:]) -> OfficePlan {
        let keys = ["/a", "/b", "/c", "/d"]
        let members = keys.flatMap { key in (0..<desks).map { OfficePlan.Member(id: "\(key)-\($0)", roomKey: key) } }
        let plan = OfficePlan.make(members, slots: OfficePlan.assignSlots(members, previous: [:]))
        return plan.applying(deskOrientation: orientation)
            .applying(decor: Dictionary(uniqueKeysWithValues: plan.rooms.map { ($0.key, decor) }))
    }

    static var configurations: [(Int, DeskOrientation)] {
        [1, 2, 3, 5, 8].flatMap { n in DeskOrientation.allCases.map { (n, $0) } }
    }

    @Test func slotsSitInsideTheRoomAwayFromFurniture() {
        for (n, orientation) in Self.configurations {
            let plan = Self.plan(desks: n, orientation: orientation)
            #expect(plan.rooms.contains { $0.decorSlots.contains { $0.id == "backWall" } }, "arka duvar yuvası (ilk odalar)")
            #expect(plan.rooms.contains { !$0.decorSlots.contains { $0.id == "backWall" } }, "alçak arka duvarda yok")
            for room in plan.rooms {
                for slot in room.decorSlots {
                    for decor in RoomDecor.allCases where slot.accepts(decor) {
                        let p = slot.placement(of: decor)
                        let f = decor.footprint
                        #expect(room.rect.contains(x: p.x, z: p.z), "\(slot.id) \(decor)")
                        guard decor.mount == .floor else { continue }
                        for spot in room.spots {
                            let gap = hypot(spot.x - p.x, spot.z - p.z) - max(f.along, f.across) - max(spot.footprint.along, spot.footprint.across)
                            #expect(gap > -0.15, "\(slot.id) \(decor) ↔ \(spot.kind)")
                        }
                        #expect(PlanPoint(x: p.x, z: p.z).distance(to: room.doorInside) > 0.8)
                    }
                }
            }
        }
    }

    @Test func everyAcceptedItemKeepsTheRoomWalkable() {
        for (n, orientation) in Self.configurations {
            let probe = Self.plan(desks: n, orientation: orientation)
            for slot in probe.rooms[0].decorSlots where slot.mount == .floor {
                for decor in RoomDecor.allCases where slot.accepts(decor) {
                    let room = Self.plan(desks: n, orientation: orientation, decor: [slot.id: decor]).rooms[0]
                    #expect(room.decor.contains { $0.slot.id == slot.id && $0.decor == decor })
                    let nav = RoomNav(room: room)
                    var targets = room.desks.flatMap { [room.seat(for: $0), room.standSpot(for: $0)] }
                    targets += room.spots.map { room.approach(to: $0).stand }
                    for target in targets {
                        #expect(nav.path(from: room.doorInside, to: target) != nil, "\(n) \(orientation) \(slot.id)=\(decor) → \(target)")
                    }
                }
            }
        }
    }

    @Test func slotsAcceptOnlyFittingItems() {
        let room = Self.plan(desks: 2, orientation: .horizontal).rooms[0]
        let side = room.decorSlots.first { $0.id == "side" }!
        let lounge = room.decorSlots.first { $0.id == "lounge" }!
        let wall = room.decorSlots.first { $0.id == "sofaWall" }!
        #expect(side.accepts(.floorLamp) && side.accepts(.fileCabinet) && !side.accepts(.vendingMachine) && !side.accepts(.wallClock))
        #expect(lounge.accepts(.vendingMachine) && lounge.accepts(.beanbag))
        #expect(wall.accepts(.corkboard) && !wall.accepts(.printer))
        // Varsayılan adayların hepsi yuvaya sığar.
        for slot in room.decorSlots { #expect(slot.defaults.compactMap { $0 }.allSatisfy(slot.accepts)) }
    }

    @Test func defaultsAreStableAndVaried() {
        let rooms = (0..<40).map { i -> OfficePlan.Room in
            let members = [OfficePlan.Member(id: "s\(i)", roomKey: "/project-\(i)")]
            return OfficePlan.make(members, slots: OfficePlan.assignSlots(members, previous: [:])).rooms[0]
        }
        let first = rooms.map { $0.decor.map(\.decor) }
        #expect(first == rooms.map { $0.decor.map(\.decor) })
        #expect(Set(rooms.compactMap { $0.decor.first { $0.slot.id == "lounge" }?.decor }).count >= 4)
    }

    @Test func choicesOverrideDefaultsAndPersist() throws {
        let empty: RoomDecor? = nil
        let choices: [String: RoomDecor?] = ["lounge": empty, "side": RoomDecor.cactus, "sofaWall": RoomDecor.picture]
        let plan = Self.plan(desks: 2, orientation: .horizontal, decor: choices)
        let room = plan.rooms[0]
        #expect(!room.decor.contains { $0.slot.id == "lounge" })
        #expect(room.decor.contains { $0.slot.id == "side" && $0.decor == .cactus })
        // Uymayan seçim yok sayılır.
        let wrong = Self.plan(desks: 2, orientation: .horizontal, decor: ["side": .vendingMachine]).rooms[0]
        #expect(!wrong.decor.contains { $0.slot.id == "side" })

        var style = RoomStyle.default(for: "/a")
        style.decor = ["lounge": empty, "side": RoomDecor.cactus]
        #expect(try JSONDecoder().decode(RoomStyle.self, from: JSONEncoder().encode(style)) == style)
        let old = #"{"wallpaper":1,"floor":0,"rug":"dots"}"#
        #expect(try JSONDecoder().decode(RoomStyle.self, from: Data(old.utf8)).decor.isEmpty)
        let unknown = #"{"wallpaper":1,"floor":0,"rug":"dots","decor":{"side":"rocket","lounge":"none"}}"#
        let expected: [String: RoomDecor?] = ["lounge": empty]
        #expect(try JSONDecoder().decode(RoomStyle.self, from: Data(unknown.utf8)).decor == expected)
    }

    @Test func artHasEveryDecorProp() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/OfficeArt/office-art.json")
        let art = try OfficeArtFile.load(from: url)
        for decor in RoomDecor.allCases {
            let prop = try #require(art.props[decor.prop], "\(decor)")
            #expect(prop.indices.count / 3 < 1200, "\(decor) hafif kalsın")
        }
    }
}
