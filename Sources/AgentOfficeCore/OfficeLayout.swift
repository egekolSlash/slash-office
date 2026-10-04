public struct TilePlacement: Equatable, Sendable {
    public var id: String
    public var column: Int
    public var row: Int
    public var project: String

    public init(id: String, column: Int, row: Int, project: String) {
        self.id = id
        self.column = column
        self.row = row
        self.project = project
    }
}

/// Karoları projeye göre satırlara yerleştirir (spec §5). Proje sırası, projenin ilk oturumunun sırasıdır.
public enum OfficeLayout {
    public static func place(_ sessions: [(id: String, project: String)], maxPerRow: Int = 4) -> [TilePlacement] {
        var order: [String] = []
        var groups: [String: [String]] = [:]
        for session in sessions {
            if groups[session.project] == nil { order.append(session.project) }
            groups[session.project, default: []].append(session.id)
        }
        var placements: [TilePlacement] = []
        var row = 0
        for project in order {
            let ids = groups[project] ?? []
            for (index, id) in ids.enumerated() {
                placements.append(TilePlacement(id: id, column: index % maxPerRow, row: row + index / maxPerRow, project: project))
            }
            row += (ids.count + maxPerRow - 1) / maxPerRow
        }
        return placements
    }

    public static func gridSize(_ placements: [TilePlacement]) -> (columns: Int, rows: Int) {
        guard !placements.isEmpty else { return (0, 0) }
        return ((placements.map(\.column).max() ?? 0) + 1, (placements.map(\.row).max() ?? 0) + 1)
    }
}

/// Projeye sabit bir renk verir. Swift'in `hashValue`'su her çalıştırmada değiştiği için FNV-1a kullanılır.
public enum ProjectPalette {
    public static let colors: [(red: Double, green: Double, blue: Double)] = [
        (0.36, 0.55, 0.85), (0.30, 0.68, 0.55), (0.80, 0.55, 0.30), (0.62, 0.45, 0.80),
        (0.80, 0.42, 0.50), (0.35, 0.65, 0.72), (0.70, 0.66, 0.32), (0.52, 0.56, 0.62),
    ]

    public static func index(for project: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in project.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % UInt64(colors.count))
    }
}
