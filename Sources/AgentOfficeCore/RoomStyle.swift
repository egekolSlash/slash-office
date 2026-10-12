/// Odanın duvar kâğıdı, zemini ve halısı (spec §7). Varsayılanı depo anahtarından türer.
public struct RoomStyle: Codable, Equatable, Hashable, Sendable {
    public enum RugPattern: String, Codable, CaseIterable, Sendable { case dots, stripes, plain }
    public static let wallpaperCount = 5
    public static let floorCount = 3
    public var wallpaper: Int
    public var floor: Int
    public var rug: RugPattern
    /// Odadaki eşyalar; eski kayıtlarda yoksa hepsi.
    public var furniture: Set<RoomFurniture>
    /// Dekor yuvası → eşya ya da nil (boş bırakıldı); kaydı olmayan yuva varsayılanını alır.
    public var decor: [String: RoomDecor?]

    public init(wallpaper: Int, floor: Int, rug: RugPattern, furniture: Set<RoomFurniture> = RoomFurniture.all,
                decor: [String: RoomDecor?] = [:]) {
        self.wallpaper = wallpaper; self.floor = floor; self.rug = rug; self.furniture = furniture; self.decor = decor
    }

    enum CodingKeys: String, CodingKey { case wallpaper, floor, rug, furniture, decor }
    static let emptyDecor = "none"

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wallpaper = try c.decode(Int.self, forKey: .wallpaper)
        floor = try c.decode(Int.self, forKey: .floor)
        rug = try c.decode(RugPattern.self, forKey: .rug)
        // Tanınmayan eşya adları atlanır.
        let names = try c.decodeIfPresent([String].self, forKey: .furniture)
        furniture = names.map { Set($0.compactMap(RoomFurniture.init(rawValue:))) } ?? RoomFurniture.all
        // Dekor: "none" boş; tanınmayan eşya adı varsayılana bırakılır.
        let raw = try c.decodeIfPresent([String: String].self, forKey: .decor) ?? [:]
        decor = raw.reduce(into: [:]) { result, item in
            if item.value == Self.emptyDecor { result[item.key] = .some(nil) }
            else if let d = RoomDecor(rawValue: item.value) { result[item.key] = .some(d) }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(wallpaper, forKey: .wallpaper)
        try c.encode(floor, forKey: .floor)
        try c.encode(rug, forKey: .rug)
        try c.encode(furniture.map(\.rawValue).sorted(), forKey: .furniture)
        if !decor.isEmpty {
            try c.encode(decor.mapValues { $0?.rawValue ?? Self.emptyDecor }, forKey: .decor)
        }
    }

    public static func `default`(for roomKey: String) -> RoomStyle {
        let h = StableHash.mixed(roomKey)
        return RoomStyle(wallpaper: Int(h % UInt64(wallpaperCount)), floor: Int((h >> 8) % UInt64(floorCount)),
                         rug: RugPattern.allCases[Int((h >> 16) % UInt64(RugPattern.allCases.count))])
    }
}
