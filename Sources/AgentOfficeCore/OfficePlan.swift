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

/// Ofisin kat planı (v5 spec §4): oda = depo, odalar koridorun iki yanında arka arkaya, masalar iki sırada ve
/// sabit yerlerde. Oda masa ekledikçe koridordan dışa doğru genişler; derinliği sabittir. Küçük z arkadadır
/// (kamera +z tarafından bakar).
public struct OfficePlan: Equatable, Sendable {
    public static let corridorX = 3.0
    public static let corridorWidth = 2.0
    public static let roomDepth = 7.4
    public static let columnSpacing = 1.9
    public static let sideMargin = 0.5
    /// Oda z'sine göre: arka ve ön masa sırası, kapının ve yürüme şeridinin hizası.
    public static let backRowZ = 1.3
    public static let frontRowZ = 3.1
    public static let walkwayZ = 4.4
    /// Arsa tabelası arsanın arka tarafında (uzak görünümde arsanın sadece başı görünür).
    public static let lotSignZ = 1.4
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
        public var width: Double
        public var depth: Double
        public var side: Side
        public var desks: [Desk]
        /// Odadaki eşyalar (oda stilinden, `OfficePlan.applying(furniture:)`).
        public var furniture: Set<RoomFurniture> = RoomFurniture.all

        public var title: String { (key as NSString).lastPathComponent }
        public var rect: PlanRect { PlanRect(minX: x, minZ: z, maxX: x + width, maxZ: z + depth) }
        /// Koridora bakan duvarın x'i ve dışa doğru yön (sol oda −1, sağ oda +1).
        public var corridorEdgeX: Double { side == .left ? x + width : x }
        public var outward: Double { side == .left ? -1 : 1 }
        /// Kapı koridora bakan duvarda, masa sıralarının önündeki yürüme şeridi hizasında.
        public var doorX: Double { corridorEdgeX }
        public var doorZ: Double { z + OfficePlan.walkwayZ }
        /// Arka duvar sadece her taraftaki ilk odada tam boy: öndeki odanın arka duvarı arkadakini örtmesin.
        /// Dış yan duvar tam boy; koridor tarafı ve ön duvar alçaktır.
        public var backWallHeight: Double { z == 0 ? OfficePlan.wallHeight : OfficePlan.lowWallHeight }
    }

    public var rooms: [Room]
    public var corridor: PlanRect
    public var bounds: PlanRect
    /// Sıradaki iki odanın yeri (sol, sağ): boş arsa olarak gösterilir.
    public var lots: [PlanRect]

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

    /// Masa sütunu sayısına göre oda genişliği (en az iki sütunluk).
    static func roomWidth(slotCount: Int) -> Double {
        Double(max(2, (slotCount + 1) / 2)) * columnSpacing + 2 * sideMargin
    }

    /// Masa `index`: sütun `index / 2` (koridordan dışa doğru), sıra `index % 2` (arka, ön). Oda büyüyünce
    /// mevcut masalar yerinde kalır.
    static func deskPosition(index: Int, corridorEdgeX: Double, outward: Double, roomZ: Double) -> (x: Double, z: Double) {
        let column = Double(index / 2)
        return (corridorEdgeX + outward * (sideMargin + columnSpacing / 2 + column * columnSpacing),
                roomZ + (index % 2 == 0 ? backRowZ : frontRowZ))
    }

    /// `order`: `roomOrder` sonucu; verilmezse odalar oturum listesinde ilk görüldükleri sırayla dizilir.
    public static func make(_ members: [Member], slots: [String: DeskSlot], order: [String]? = nil) -> OfficePlan {
        var groups: [String: [Member]] = [:]
        for member in members { groups[member.roomKey, default: []].append(member) }
        let order = roomOrder(members, previous: order ?? [])
        var rooms: [Room] = []
        var cursor: [Side: Double] = [.left: 0, .right: 0]
        func origin(_ side: Side, width: Double) -> Double {
            side == .left ? corridorX - width : corridorX + corridorWidth
        }
        for (position, key) in order.enumerated() {
            let group = groups[key] ?? []
            let indices = group.map { slots[$0.id]?.index ?? 0 }
            let width = roomWidth(slotCount: (indices.max() ?? 0) + 1)
            let side: Side = position % 2 == 0 ? .left : .right
            let x = origin(side, width: width)
            let z = cursor[side] ?? 0
            cursor[side] = z + roomDepth
            var room = Room(key: key, x: x, z: z, width: width, depth: roomDepth, side: side, desks: [])
            room.desks = zip(group, indices).map { member, index in
                let p = deskPosition(index: index, corridorEdgeX: room.corridorEdgeX, outward: room.outward, roomZ: z)
                return Desk(id: member.id, x: p.x, z: p.z)
            }
            rooms.append(room)
        }
        let length = max(cursor[.left] ?? 0, cursor[.right] ?? 0)
        let corridor = PlanRect(minX: corridorX, minZ: 0, maxX: corridorX + corridorWidth, maxZ: length)
        let bounds = rooms.isEmpty ? PlanRect.zero
            : PlanRect(minX: rooms.map(\.x).min() ?? 0, minZ: 0,
                       maxX: rooms.map { $0.x + $0.width }.max() ?? 0, maxZ: length)
        // Sıradaki oda: sayıca az olan taraf önce (eşitse sol); arsalar her iki tarafın sıradaki yerinde.
        let lotWidth = roomWidth(slotCount: 1)
        let lots = [Side.left, .right].map { side in
            let x = origin(side, width: lotWidth), z = cursor[side] ?? 0
            return PlanRect(minX: x, minZ: z, maxX: x + lotWidth, maxZ: z + roomDepth)
        }
        return OfficePlan(rooms: rooms, corridor: corridor, bounds: bounds, lots: lots)
    }

    /// Zemindeki noktanın denk geldiği arsa (`lots` sırası).
    public func lot(atX x: Double, z: Double) -> Int? {
        lots.firstIndex { $0.contains(x: x, z: z) }
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
