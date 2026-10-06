/// Odanın duvar kâğıdı, zemini ve halısı (spec §7). Varsayılanı depo anahtarından türer.
public struct RoomStyle: Codable, Equatable, Hashable, Sendable {
    public enum RugPattern: String, Codable, CaseIterable, Sendable { case dots, stripes, plain }
    public static let wallpaperCount = 5
    public static let floorCount = 3
    public var wallpaper: Int
    public var floor: Int
    public var rug: RugPattern

    public init(wallpaper: Int, floor: Int, rug: RugPattern) {
        self.wallpaper = wallpaper; self.floor = floor; self.rug = rug
    }

    public static func `default`(for roomKey: String) -> RoomStyle {
        let h = StableHash.mixed(roomKey)
        return RoomStyle(wallpaper: Int(h % UInt64(wallpaperCount)), floor: Int((h >> 8) % UInt64(floorCount)),
                         rug: RugPattern.allCases[Int((h >> 16) % UInt64(RugPattern.allCases.count))])
    }
}
