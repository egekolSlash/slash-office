import Foundation
import simd

/// Minyon (arka plan işi kedisi) paketi: `Resources/Minion/minion.json` + `tex/` (`tools/minion/build_minion.py`).
/// Meshler `character.json` biçiminde; parçalar katıdır (her mesh tek kemiğe bağlı), animasyon `MinionPose`'ta kodla.
public struct MinionArt: Sendable {
    public var directory: URL
    /// Kulak ucu dahil boy (metre).
    public var height: Float
    public var bones: [String]
    public var parents: [Int]
    /// Kemiklerin dönme noktaları (uygulama uzayı, minyonun yerel koordinatı).
    public var pivots: [SIMD3<Float>]
    public var meshes: [String: CharacterArt.Mesh]
    public var parts: [CharacterArt.Part]

    public static let fileName = "minion.json"
    public static let boneNames = ["body", "head", "leg_L", "leg_R", "tail"]

    /// Uygulama paketindeki `Minion` klasörü, yoksa depodaki `Resources/Minion` (geliştirme).
    public static func find(bundleResources: URL?, repoRoot: URL, fileManager: FileManager = .default) -> URL? {
        [bundleResources?.appendingPathComponent("Minion"), repoRoot.appendingPathComponent("Resources/Minion")]
            .compactMap { $0 }
            .first { fileManager.fileExists(atPath: $0.appendingPathComponent(fileName).path) }
    }

    public static func load(directory: URL) throws -> MinionArt {
        try decode(Data(contentsOf: directory.appendingPathComponent(fileName)), directory: directory)
    }

    public static func decode(_ data: Data, directory: URL) throws -> MinionArt {
        struct Raw: Decodable {
            var height: Float
            var bones: [String]
            var parents: [Int]
            var pivots: [[Float]]
            var meshes: [String: CharacterArt.RawMesh]
            var parts: [CharacterArt.Part]
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        typealias F = OfficeArtFile
        // Poz kodu kemikleri adla değil sırayla kullanır.
        guard raw.bones == boneNames, raw.parents.count == raw.bones.count, raw.pivots.count == raw.bones.count,
              raw.pivots.allSatisfy({ $0.count == 3 }),
              raw.parents.enumerated().allSatisfy({ $0.element < $0.offset }) else { throw F.Failure.badLength("minion skeleton") }
        let meshes = try CharacterArt.decodeMeshes(raw.meshes, boneCount: raw.bones.count)
        if let missing = raw.parts.first(where: { meshes[$0.mesh] == nil }) { throw F.Failure.indexOutOfRange(missing.mesh) }
        return MinionArt(directory: directory, height: raw.height, bones: raw.bones, parents: raw.parents,
                         pivots: raw.pivots.map { SIMD3($0[0], $0[1], $0[2]) }, meshes: meshes, parts: raw.parts)
    }
}
