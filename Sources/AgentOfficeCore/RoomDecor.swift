import Foundation

/// Odaların dekor eşyaları: odanın sabit yuvalarına (dış duvar dibinde zemin yuvaları, koltuğun üstünde ve tam boy arka
/// duvarda duvar yuvaları) konur. Varsayılanı oda anahtarından türer; oda düzenleyicisinden yuva yuva değişir.
/// Zemin eşyaları köylüler için engeldir.
public enum RoomDecor: String, CaseIterable, Codable, Sendable {
    case printer, fileCabinet, serverRack, miniFridge, vendingMachine, beanbag, floorLamp, bigPlant, cactus, trashBin
    case wallClock, corkboard, picture

    public var mount: DecorSlot.Mount {
        switch self {
        case .wallClock, .corkboard, .picture: .wall
        default: .floor
        }
    }

    /// Eşyanın tabanı: duvardan içeri (bakış yönü boyunca) ve duvar boyunca yarı uzunluklar; yuvarlaklarda yarıçap.
    /// Duvar eşyalarında duvar boyunca yarı genişlik.
    public var footprint: (along: Double, across: Double, round: Bool) {
        switch self {
        case .printer: (0.28, 0.43, false)
        case .fileCabinet: (0.25, 0.22, false)
        case .serverRack: (0.31, 0.27, false)
        case .miniFridge: (0.26, 0.25, false)
        case .vendingMachine: (0.35, 0.37, false)
        case .beanbag: (0.41, 0.41, true)
        case .floorLamp: (0.20, 0.20, true)
        case .bigPlant: (0.30, 0.30, true)
        case .cactus: (0.15, 0.15, true)
        case .trashBin: (0.15, 0.15, true)
        case .wallClock: (0.06, 0.17, false)
        case .corkboard: (0.05, 0.42, false)
        case .picture: (0.07, 0.18, false)
        }
    }

    /// `office-art` eşyası (tools/furniture/build_furniture.py): ön yüz +x.
    public var prop: String {
        switch self {
        case .printer: "decor_printer"
        case .fileCabinet: "decor_file_cabinet"
        case .serverRack: "decor_server_rack"
        case .miniFridge: "decor_mini_fridge"
        case .vendingMachine: "decor_vending_machine"
        case .beanbag: "decor_beanbag"
        case .floorLamp: "decor_floor_lamp"
        case .bigPlant: "decor_big_plant"
        case .cactus: "decor_cactus"
        case .trashBin: "decor_trash_bin"
        case .wallClock: "decor_wall_clock"
        case .corkboard: "decor_corkboard"
        case .picture: "decor_picture"
        }
    }
}

/// Dekor yuvası: duvarın üstünde bir nokta ve odaya bakan yön. Zemin eşyası arkasını duvara verip odaya doğru
/// konur; duvar eşyası `height` yüksekliğinde asılır.
public struct DecorSlot: Equatable, Sendable {
    public enum Mount: String, Sendable { case floor, wall }
    public var id: String
    public var mount: Mount
    /// Duvar üstündeki nokta.
    public var x: Double
    public var z: Double
    /// Odaya bakan yön (y ekseni etrafında, 0 = +z).
    public var facing: Double
    public var height: Double
    /// Sığan eşyalar: duvardan en fazla derinlik ve duvar boyunca en fazla yarı genişlik.
    public var maxDepth: Double
    public var maxHalf: Double
    /// Varsayılan seçimin adayları (nil: boş).
    public var defaults: [RoomDecor?]

    public func accepts(_ decor: RoomDecor) -> Bool {
        let f = decor.footprint
        return decor.mount == mount && f.along * 2 + 0.03 <= maxDepth && f.across <= maxHalf
    }

    /// Eşyanın konumu (merkez ya da duvar eşyasında arka yüz ortası) ve yönü.
    public func placement(of decor: RoomDecor) -> (x: Double, z: Double, y: Double, facing: Double) {
        let dir = (x: sin(facing), z: cos(facing))
        let offset = mount == .wall ? 0.005 : decor.footprint.along + 0.03
        return (x + dir.x * offset, z + dir.z * offset, mount == .wall ? height : 0, facing)
    }
}

extension OfficePlan.Room {
    /// Dekor yuvaları: dış duvar dibinde pencere ile saksı arası (ince eşyalar) ve koltuk ile atari arası, koltuğun
    /// üstünde duvar; arka duvar tam boysa (her taraftaki ilk oda) pencere ile dış köşe arasında bir duvar yuvası daha.
    public var decorSlots: [DecorSlot] {
        let outer = corridorEdgeX + outward * width
        let inward = outward > 0 ? -Double.pi / 2 : Double.pi / 2
        var slots = [
            DecorSlot(id: "side", mount: .floor, x: outer, z: z + 3.34, facing: inward, height: 0, maxDepth: 0.66, maxHalf: 0.42,
                      defaults: [.bigPlant, .floorLamp, .cactus, .fileCabinet, .trashBin, nil]),
            DecorSlot(id: "lounge", mount: .floor, x: outer, z: z + 6.0, facing: inward, height: 0, maxDepth: 0.85, maxHalf: 0.45,
                      defaults: [.vendingMachine, .miniFridge, .printer, .beanbag, .serverRack, .bigPlant, nil]),
            DecorSlot(id: "sofaWall", mount: .wall, x: outer, z: z + 4.95, facing: inward, height: 1.08, maxDepth: 0.2, maxHalf: 0.5,
                      defaults: [.corkboard, .picture, .wallClock, nil]),
        ]
        if backWallHeight > 1 {
            // Arka duvarda pencerenin dış kenarı ile dış köşe arası (pencere oda ortasında, yarı genişliği ~0,6; tahta
            // koridor tarafında).
            let windowFar = x + width / 2 + outward * 0.65
            let corner = outer - outward * 0.35
            let length = abs(corner - windowFar)
            if length >= 0.6 {
                slots.append(DecorSlot(id: "backWall", mount: .wall, x: (corner + windowFar) / 2, z: z, facing: 0, height: 1.1,
                                       maxDepth: 0.2, maxHalf: min(0.45, length / 2 - 0.05), defaults: [.wallClock, .picture, .corkboard]))
            }
        }
        return slots
    }

    /// Yuva → seçilen eşya (oda stilinden, `OfficePlan.applying(decor:)`); kaydı olmayan yuva varsayılanını alır.
    public func decorItems(choices: [String: RoomDecor?]) -> [(slot: DecorSlot, decor: RoomDecor)] {
        decorSlots.compactMap { slot in
            let choice: RoomDecor? = choices[slot.id] ?? Self.defaultDecor(slot: slot, roomKey: key)
            guard let decor = choice, slot.accepts(decor) else { return nil }
            return (slot, decor)
        }
    }

    public static func defaultDecor(slot: DecorSlot, roomKey: String) -> RoomDecor? {
        let h = StableHash.mixed("decor:" + roomKey + ":" + slot.id)
        return slot.defaults[Int(h % UInt64(slot.defaults.count))]
    }

    /// Odada duran dekor (yuva ve eşya).
    public var decor: [(slot: DecorSlot, decor: RoomDecor)] { decorItems(choices: decorChoices) }
}

extension OfficePlan {
    /// Odaların dekor seçimleri (oda stilinden); listede olmayan oda varsayılanları alır.
    public func applying(decor: [String: [String: RoomDecor?]]) -> OfficePlan {
        var plan = self
        for i in plan.rooms.indices { plan.rooms[i].decorChoices = decor[plan.rooms[i].key] ?? [:] }
        return plan
    }
}
