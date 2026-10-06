import Foundation

/// Projeye sabit bir renk verir. Swift'in `hashValue`'su her çalıştırmada değiştiği için FNV-1a kullanılır.
public enum ProjectPalette {
    public static let colors: [(red: Double, green: Double, blue: Double)] = [
        (0.36, 0.55, 0.85), (0.30, 0.68, 0.55), (0.80, 0.55, 0.30), (0.62, 0.45, 0.80),
        (0.80, 0.42, 0.50), (0.35, 0.65, 0.72), (0.70, 0.66, 0.32), (0.52, 0.56, 0.62),
    ]

    public static func index(for project: String) -> Int {
        Int(StableHash.fnv1a(project) % UInt64(colors.count))
    }
}
