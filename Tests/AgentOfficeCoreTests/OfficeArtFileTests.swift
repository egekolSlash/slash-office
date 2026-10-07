import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct OfficeArtFileTests {
    static func b64<T>(_ values: [T]) -> String {
        values.withUnsafeBytes { Data($0).base64EncodedString() }
    }

    static let sample = """
    {"version": 1, "bones": ["Root", "Hips"],
     "clips": {"idle": {"frames": 1, "matrices": "\(b64([Float](repeating: 1, count: 32)))"}},
     "villager": {"vertexCount": 3, "positions": "\(b64((0..<9).map(Float.init)))",
                  "normals": "\(b64([Float](repeating: 0, count: 9)))", "uvs": "\(b64([Float](repeating: 0.5, count: 6)))",
                  "colors": "\(b64([UInt8](repeating: 255, count: 12)))", "indices": "\(b64([UInt32]([0, 1, 2])))",
                  "bones": "\(b64([UInt8]([0, 1, 1])))", "parts": "\(b64([UInt8]([0, 1, 4])))", "hair": "\(b64([UInt8]([0, 0, 2])))"},
     "props": {"lamp": {"vertexCount": 3, "positions": "\(b64([Float](repeating: 2, count: 9)))",
                        "normals": "\(b64([Float](repeating: 0, count: 9)))", "uvs": "\(b64([Float](repeating: 0, count: 6)))",
                        "colors": "\(b64([UInt8](repeating: 9, count: 12)))", "indices": "\(b64([UInt32]([2, 1, 0])))"}}}
    """

    @Test func decodesSample() throws {
        let art = try OfficeArtFile.decode(Data(Self.sample.utf8))
        #expect(art.bones == ["Root", "Hips"])
        #expect(art.clips["idle"]?.frames == 1)
        #expect(art.clips["idle"]?.matrices.count == 32)
        #expect(art.villager.positions == (0..<9).map(Float.init))
        #expect(art.villager.parts == [0, 1, 4])
        #expect(art.villager.hair == [0, 0, 2])
        #expect(art.villager.bones == [0, 1, 1])
        #expect(art.villager.vertexCount == 3)
        let lamp = try #require(art.props["lamp"])
        #expect(lamp.indices == [2, 1, 0])
        #expect(lamp.colors.count == 12)
        #expect(lamp.bones.isEmpty && lamp.parts.isEmpty && lamp.hair.isEmpty)
    }

    @Test func realArtFileIsSane() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/OfficeArt/office-art.json")
        let art = try OfficeArtFile.load(from: url)
        #expect(art.bones.count == 11)
        #expect(art.clips["walk"]?.frames == 24)
        for clip in AvatarClip.allCases {
            let data = try #require(art.clips[clip.rawValue])
            #expect(data.frames == clip.frames.count)
            #expect(data.matrices.count == data.frames * art.bones.count * 16)
        }
        #expect(Set(art.villager.parts) == [0, 1, 2, 3, 4])
        #expect(Set(art.villager.hair) == [0, 1, 2, 3, 4])
        #expect(art.villager.bones.allSatisfy { Int($0) < art.bones.count })
        for (name, mesh) in art.props.merging(["villager": art.villager], uniquingKeysWith: { a, _ in a }) {
            #expect(mesh.indices.count % 3 == 0, "\(name)")
            #expect(mesh.indices.allSatisfy { Int($0) < mesh.vertexCount }, "\(name)")
            #expect(mesh.positions.count == mesh.vertexCount * 3 && mesh.normals.count == mesh.vertexCount * 3, "\(name)")
            #expect(mesh.uvs.count == mesh.vertexCount * 2 && mesh.colors.count == mesh.vertexCount * 4, "\(name)")
        }
        #expect(Set(art.props.keys).isSuperset(of: ["desk_set", "terminal_set", "bookshelf", "plant", "lamp",
                                                    "tree", "flower", "window", "curtain",
                                                    "sofa", "coffee_table", "water_cooler", "hill_a", "hill_b", "hill_c", "tree_b"]))
        // Tepeler bükülme için z'de sık bölünmüş olmalı: hiçbir üçgen z'de 1 m'den uzun değil.
        for name in ["hill_a", "hill_b", "hill_c"] {
            let hill = try #require(art.props[name])
            for t in stride(from: 0, to: hill.indices.count, by: 3) {
                let zs = (0..<3).map { hill.positions[Int(hill.indices[t + $0]) * 3 + 2] }
                #expect(zs.max()! - zs.min()! <= 1.0, "\(name) üçgen \(t / 3)")
            }
        }
    }

    @Test func missingOrCorruptArtFile() throws {
        let missing = URL(fileURLWithPath: "/nonexistent/office-art.json")
        #expect(throws: (any Error).self) { try OfficeArtFile.load(from: missing) }
        #expect(throws: (any Error).self) { try OfficeArtFile.decode(Data("{\"version\": 1}".utf8)) }
        let badBase64 = Self.sample.replacingOccurrences(of: "\"indices\": \"", with: "\"indices\": \"%%")
        #expect(throws: (any Error).self) { try OfficeArtFile.decode(Data(badBase64.utf8)) }
        // Dizi uzunlukları köşe sayısına uymuyorsa
        let short = Self.sample.replacingOccurrences(of: "\"vertexCount\": 3, \"positions\"", with: "\"vertexCount\": 4, \"positions\"")
        #expect(throws: (any Error).self) { try OfficeArtFile.decode(Data(short.utf8)) }
        // İndeks sınır dışında
        let outOfRange = Self.sample.replacingOccurrences(of: Self.b64([UInt32]([2, 1, 0])), with: Self.b64([UInt32]([2, 1, 7])))
        #expect(throws: (any Error).self) { try OfficeArtFile.decode(Data(outOfRange.utf8)) }
        // Köşenin kemiği iskelette yok (GPU başka köylünün matrisini okurdu).
        let badBone = Self.sample.replacingOccurrences(of: Self.b64([UInt8]([0, 1, 1])), with: Self.b64([UInt8]([0, 1, 5])))
        #expect(throws: (any Error).self) { try OfficeArtFile.decode(Data(badBone.utf8)) }
    }
}
