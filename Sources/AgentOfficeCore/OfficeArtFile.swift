import Foundation

/// Blender'ın yazdığı `office-art.json` (tools/office-art/build_assets.py): ofisin eşyaları (Y-yukarı mesh'ler); yanında
/// `furniture.json` (dekor eşyaları, tools/furniture) varsa onlar da eklenir. Köylüler ayrı: `CharacterArt`.
/// Sayısal diziler base64 kodlanmış küçük-sonlu float32 / uint32 / uint8'dir.
public struct OfficeArtFile: Sendable {
    public var props: [String: ArtMesh]

    public enum Failure: Error, Equatable {
        case badBase64(String)
        case badLength(String)
        case indexOutOfRange(String)
    }

    public static func load(from url: URL) throws -> OfficeArtFile {
        var art = try decode(Data(contentsOf: url))
        let furniture = url.deletingLastPathComponent().appendingPathComponent("furniture.json")
        if let data = try? Data(contentsOf: furniture) {
            art.props.merge(try decode(data).props) { _, new in new }
        }
        return art
    }

    public static func decode(_ data: Data) throws -> OfficeArtFile {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        return OfficeArtFile(props: try raw.props.reduce(into: [:]) { $0[$1.key] = try ArtMesh($1.value, name: $1.key) })
    }

    static func array<T>(_ text: String, _ name: String) throws -> [T] {
        guard let data = Data(base64Encoded: text), data.count % MemoryLayout<T>.stride == 0 else {
            throw Failure.badBase64(name)
        }
        return data.withUnsafeBytes { Array($0.bindMemory(to: T.self)) }
    }

    struct Raw: Decodable {
        var props: [String: RawMesh]
    }

    /// Karakter paketinin klipleri de bu biçimde.
    struct RawClip: Decodable {
        var frames: Int
        var matrices: String
    }

    struct RawMesh: Decodable {
        var vertexCount: Int
        var positions, normals, uvs, colors, indices: String
    }
}

public struct ArtClip: Sendable {
    public var frames: Int
    /// Kare × kemik × 16, sütun sıralı skinning matrisleri.
    public var matrices: [Float]
}

public struct ArtMesh: Sendable {
    public var vertexCount: Int
    public var positions: [Float]
    public var normals: [Float]
    public var uvs: [Float]
    /// RGBA (sRGB); A = emissive × 255.
    public var colors: [UInt8]
    public var indices: [UInt32]

    init(_ raw: OfficeArtFile.RawMesh, name: String) throws {
        typealias F = OfficeArtFile
        vertexCount = raw.vertexCount
        positions = try F.array(raw.positions, name)
        normals = try F.array(raw.normals, name)
        uvs = try F.array(raw.uvs, name)
        colors = try F.array(raw.colors, name)
        indices = try F.array(raw.indices, name)
        let n = vertexCount
        guard positions.count == n * 3, normals.count == n * 3, uvs.count == n * 2, colors.count == n * 4,
              indices.count % 3 == 0 else { throw F.Failure.badLength(name) }
        guard indices.allSatisfy({ Int($0) < n }) else { throw F.Failure.indexOutOfRange(name) }
    }
}

extension ArtMesh {
    init(vertexCount: Int, positions: [Float], normals: [Float], uvs: [Float], colors: [UInt8], indices: [UInt32]) {
        self.vertexCount = vertexCount; self.positions = positions; self.normals = normals
        self.uvs = uvs; self.colors = colors; self.indices = indices
    }
}
