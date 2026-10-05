import Foundation

/// Zemin düzleminde dikdörtgen (dünya birimi = karo).
public struct PlanRect: Equatable, Sendable {
    public var minX: Double, minZ: Double, maxX: Double, maxZ: Double

    public init(minX: Double, minZ: Double, maxX: Double, maxZ: Double) {
        self.minX = minX
        self.minZ = minZ
        self.maxX = maxX
        self.maxZ = maxZ
    }

    public static let zero = PlanRect(minX: 0, minZ: 0, maxX: 0, maxZ: 0)
    public var isEmpty: Bool { maxX <= minX || maxZ <= minZ }

    public func contains(x: Double, z: Double) -> Bool {
        x >= minX && x <= maxX && z >= minZ && z <= maxZ
    }
}

/// Ofisin kat planı (spec §3): oda = depo, odalar koridorun iki yanında, masalar sabit yerlerde.
/// Küçük x ve z arkadadır (kamera (1,1,1) yönünden bakar).
public struct OfficePlan: Equatable, Sendable {
    public static let corridorX = 3.0
    public static let corridorWidth = 1.5
    public static let wallHeight = 1.6
    /// İç ve ön duvarlar alçak (Sims tarzı kesit): arkadaki odayı ve masaları örtmez.
    public static let lowWallHeight = 0.25

    public struct Member: Equatable, Sendable {
        public var id: String
        public var roomKey: String

        public init(id: String, roomKey: String) {
            self.id = id
            self.roomKey = roomKey
        }
    }

    /// Bir oturumun odasındaki masa numarası; oturum kalkınca diğerlerininki değişmez.
    public struct DeskSlot: Equatable, Sendable {
        public var roomKey: String
        public var index: Int

        public init(roomKey: String, index: Int) {
            self.roomKey = roomKey
            self.index = index
        }
    }

    public struct Desk: Equatable, Sendable {
        public var id: String
        /// Masanın merkezi.
        public var x: Double
        public var z: Double
    }

    public enum Side: Equatable, Sendable { case left, right }

    public struct Room: Equatable, Sendable {
        public var key: String
        /// Arka köşe (en küçük x ve z).
        public var x: Double
        public var z: Double
        public var width: Int
        public var depth: Int
        public var side: Side
        public var desks: [Desk]

        public var title: String { (key as NSString).lastPathComponent }
        public var rect: PlanRect { PlanRect(minX: x, minZ: z, maxX: x + Double(width), maxZ: z + Double(depth)) }
        /// Kapı koridora bakan duvarın ortasında.
        public var doorX: Double { side == .left ? x + Double(width) : x }
        public var doorZ: Double { z + Double(depth) / 2 }
        /// Arka duvarların yüksekliği: tam boy sadece binanın dış arka kenarında (koridorun ilk odaları ve sol
        /// taraftaki dış duvar); iç duvarlar alçak, yoksa öndeki odanın duvarı arkadakinin zeminini örter.
        public var backWallHeights: (z: Double, x: Double) {
            (z == 0 ? OfficePlan.wallHeight : OfficePlan.lowWallHeight,
             side == .left ? OfficePlan.wallHeight : OfficePlan.lowWallHeight)
        }
    }

    public var rooms: [Room]
    public var corridor: PlanRect
    public var bounds: PlanRect

    /// Önceki yerini koruyan (aynı odadaysa) ve yenilere odadaki en küçük boş numarayı veren atama.
    public static func assignSlots(_ members: [Member], previous: [String: DeskSlot]) -> [String: DeskSlot] {
        var result: [String: DeskSlot] = [:]
        var used: [String: Set<Int>] = [:]
        for member in members {
            guard let slot = previous[member.id], slot.roomKey == member.roomKey,
                  !used[member.roomKey, default: []].contains(slot.index) else { continue }
            result[member.id] = slot
            used[member.roomKey, default: []].insert(slot.index)
        }
        for member in members where result[member.id] == nil {
            var index = 0
            while used[member.roomKey, default: []].contains(index) { index += 1 }
            result[member.id] = DeskSlot(roomKey: member.roomKey, index: index)
            used[member.roomKey, default: []].insert(index)
        }
        return result
    }

    /// Odaların sırası: projenin ofise ilk girdiği an (spec §3). Önceki sıradaki odalar yerini korur, odası
    /// boşalanlar çıkar, yeni projeler ilk görüldükleri sırayla sona eklenir.
    public static func roomOrder(_ members: [Member], previous: [String]) -> [String] {
        let present = Set(members.map(\.roomKey))
        var order = previous.filter(present.contains)
        for member in members where !order.contains(member.roomKey) { order.append(member.roomKey) }
        return order
    }

    /// 1–2 masa 2×2, 3–4 masa 3×2, daha fazlası 3×3 (spec §3).
    static func roomSize(slotCount: Int) -> (width: Int, depth: Int) {
        switch slotCount {
        case ...2: (2, 2)
        case 3...4: (3, 2)
        default: (3, 3)
        }
    }

    /// Masalar iki sütunda (duvar diplerinde), sıra sıra. Sıralar odaya sığmazsa aralarındaki mesafe daralır.
    static func deskOffset(index: Int, slotCount: Int, width: Int, depth: Int) -> (x: Double, z: Double) {
        let x = index % 2 == 0 ? 0.5 : Double(width) - 0.5
        let row = index / 2
        let rows = (slotCount + 1) / 2
        guard rows > depth, rows > 1 else { return (x, 0.5 + Double(row)) }
        return (x, 0.5 + Double(row) * (Double(depth) - 1) / Double(rows - 1))
    }

    /// `order`: `roomOrder` sonucu; verilmezse odalar oturum listesinde ilk görüldükleri sırayla dizilir.
    public static func make(_ members: [Member], slots: [String: DeskSlot], order: [String]? = nil) -> OfficePlan {
        var groups: [String: [Member]] = [:]
        for member in members { groups[member.roomKey, default: []].append(member) }
        let order = roomOrder(members, previous: order ?? [])
        var rooms: [Room] = []
        var cursor: [Side: Double] = [.left: 0, .right: 0]
        for (position, key) in order.enumerated() {
            let group = groups[key] ?? []
            let indices = group.map { slots[$0.id]?.index ?? 0 }
            let slotCount = (indices.max() ?? 0) + 1
            let size = roomSize(slotCount: slotCount)
            let side: Side = position % 2 == 0 ? .left : .right
            let x = side == .left ? corridorX - Double(size.width) : corridorX + corridorWidth
            let z = cursor[side] ?? 0
            cursor[side] = z + Double(size.depth)
            let desks = zip(group, indices).map { member, index in
                let offset = deskOffset(index: index, slotCount: slotCount, width: size.width, depth: size.depth)
                return Desk(id: member.id, x: x + offset.x, z: z + offset.z)
            }
            rooms.append(Room(key: key, x: x, z: z, width: size.width, depth: size.depth, side: side, desks: desks))
        }
        let length = max(cursor[.left] ?? 0, cursor[.right] ?? 0)
        let corridor = PlanRect(minX: corridorX, minZ: 0, maxX: corridorX + corridorWidth, maxZ: length)
        let bounds = rooms.isEmpty ? PlanRect.zero
            : PlanRect(minX: rooms.map(\.x).min() ?? 0, minZ: 0,
                       maxX: rooms.map { $0.x + Double($0.width) }.max() ?? 0, maxZ: length)
        return OfficePlan(rooms: rooms, corridor: corridor, bounds: bounds)
    }

    /// Zemindeki noktaya en yakın masa (masanın yarım karo çevresinde).
    public func desk(atX x: Double, z: Double) -> String? {
        let desks = rooms.flatMap(\.desks)
        let hits = desks.filter { abs($0.x - x) <= 0.5 && abs($0.z - z) <= 0.5 }
        return hits.min { hypot($0.x - x, $0.z - z) < hypot($1.x - x, $1.z - z) }?.id
    }

    public func room(atX x: Double, z: Double) -> Room? {
        rooms.first { $0.rect.contains(x: x, z: z) }
    }
}

/// Sahnedeki çizim sırası (SpriteKit `zPosition`). Aynı taraftaki odalar arka arkaya dizildiği için önce oda sırası,
/// oda içinde zemin < arka duvarlar < masalar (önden arkaya) < ön duvarlar. Sol ve sağ odalar ekranda örtüşmez.
public enum OfficeDepth {
    static func base(_ room: OfficePlan.Room) -> Double { room.z * 100 }
    public static func floor(_ room: OfficePlan.Room) -> Double { base(room) }
    public static func backWalls(_ room: OfficePlan.Room) -> Double { base(room) + 1 }
    public static func desk(_ desk: OfficePlan.Desk, in room: OfficePlan.Room) -> Double {
        base(room) + 10 + (desk.x - room.x + desk.z - room.z) * 10
    }
    public static func frontWalls(_ room: OfficePlan.Room) -> Double { base(room) + 90 }
}
