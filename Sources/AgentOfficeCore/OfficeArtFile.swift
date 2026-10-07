import Foundation

/// Blender'ın yazdığı `office-art.json` (tools/office-art/build_assets.py): Y-yukarı mesh'ler ve kliplerin kemik matrisleri.
/// Sayısal diziler base64 kodlanmış küçük-sonlu float32 / uint32 / uint8'dir.
public struct OfficeArtFile: Sendable {
    public var bones: [String]
    public var clips: [String: ArtClip]
    public var villager: ArtMesh
    public var props: [String: ArtMesh]

    public enum Failure: Error, Equatable {
        case badBase64(String)
        case badLength(String)
        case indexOutOfRange(String)
    }

    public static func load(from url: URL) throws -> OfficeArtFile {
        try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> OfficeArtFile {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        var clips: [String: ArtClip] = [:]
        for (name, clip) in raw.clips {
            let matrices: [Float] = try array(clip.matrices, "clip \(name)")
            guard matrices.count == clip.frames * raw.bones.count * 16 else { throw Failure.badLength("clip \(name)") }
            clips[name] = ArtClip(frames: clip.frames, matrices: matrices)
        }
        return OfficeArtFile(bones: raw.bones, clips: clips,
                             villager: try ArtMesh(raw.villager, name: "villager", skinned: true),
                             props: try raw.props.reduce(into: [:]) { $0[$1.key] = try ArtMesh($1.value, name: $1.key, skinned: false) })
    }

    static func array<T>(_ text: String, _ name: String) throws -> [T] {
        guard let data = Data(base64Encoded: text), data.count % MemoryLayout<T>.stride == 0 else {
            throw Failure.badBase64(name)
        }
        return data.withUnsafeBytes { Array($0.bindMemory(to: T.self)) }
    }

    struct Raw: Decodable {
        var bones: [String]
        var clips: [String: RawClip]
        var villager: RawMesh
        var props: [String: RawMesh]
    }

    struct RawClip: Decodable {
        var frames: Int
        var matrices: String
    }

    struct RawMesh: Decodable {
        var vertexCount: Int
        var positions, normals, uvs, colors, indices: String
        var bones, parts, hair: String?
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
    /// Köylüde: köşenin kemiği, parça kodu (0 sabit, 1 tişört, 2 ten, 3 saç, 4 gözlük) ve saç modeli (0 saç değil).
    public var bones: [UInt8] = []
    public var parts: [UInt8] = []
    public var hair: [UInt8] = []

    init(_ raw: OfficeArtFile.RawMesh, name: String, skinned: Bool) throws {
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
        if skinned {
            guard let b = raw.bones, let p = raw.parts, let h = raw.hair else { throw F.Failure.badLength(name) }
            bones = try F.array(b, name)
            parts = try F.array(p, name)
            hair = try F.array(h, name)
            guard bones.count == n, parts.count == n, hair.count == n else { throw F.Failure.badLength(name) }
        }
    }
}
