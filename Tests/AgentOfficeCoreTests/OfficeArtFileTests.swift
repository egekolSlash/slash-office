import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct OfficeArtFileTests {
    static func b64<T>(_ values: [T]) -> String {
        values.withUnsafeBytes { Data($0).base64EncodedString() }
    }

    static let sample = """
    {"version": 2,
     "props": {"lamp": {"vertexCount": 3, "positions": "\(b64([Float](repeating: 2, count: 9)))",
                        "normals": "\(b64([Float](repeating: 0, count: 9)))", "uvs": "\(b64([Float](repeating: 0, count: 6)))",
                        "colors": "\(b64([UInt8](repeating: 9, count: 12)))", "indices": "\(b64([UInt32]([2, 1, 0])))"}}}
    """

    @Test func decodesSample() throws {
        let art = try OfficeArtFile.decode(Data(Self.sample.utf8))
        let lamp = try #require(art.props["lamp"])
        #expect(lamp.vertexCount == 3)
        #expect(lamp.positions == [Float](repeating: 2, count: 9))
        #expect(lamp.indices == [2, 1, 0])
        #expect(lamp.colors.count == 12)
    }

    @Test func realArtFileIsSane() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/OfficeArt/office-art.json")
        let art = try OfficeArtFile.load(from: url)
        #expect(AvatarClip.sofaSit.loops && !AvatarClip.cheer.loops && AvatarClip.sitSip.seated && !AvatarClip.drink.seated)
        #expect(abs(AvatarClip.standUp.duration - 11.0 / 24) < 1e-9)
        // Ofis hayatı: masa başı ve eşya klipleri.
        #expect(AvatarClip.sitDraw.seated && AvatarClip.sitWrite.seated && AvatarClip.sitRead.seated)
        #expect(AvatarClip.readBook.loops && AvatarClip.playArcade.loops && AvatarClip.drawBoard.loops)
        #expect(!AvatarClip.stepBackLook.loops && !AvatarClip.brewCoffee.loops && !AvatarClip.brewCoffee.seated)
        for (name, mesh) in art.props {
            #expect(mesh.indices.count % 3 == 0, "\(name)")
            #expect(mesh.indices.allSatisfy { Int($0) < mesh.vertexCount }, "\(name)")
            #expect(mesh.positions.count == mesh.vertexCount * 3 && mesh.normals.count == mesh.vertexCount * 3, "\(name)")
            #expect(mesh.uvs.count == mesh.vertexCount * 2 && mesh.colors.count == mesh.vertexCount * 4, "\(name)")
        }
        #expect(Set(art.props.keys).isSuperset(of: ["desk_set", "terminal_set", "bookshelf", "plant", "lamp",
                                                    "tree", "flower", "window", "curtain",
                                                    "sofa", "coffee_table", "water_cooler", "cliff_a", "cliff_b", "cliff_c", "tree_b", "cedar",
                                                    "arcade", "whiteboard", "coffee_machine"]))
        // Büyüyen masa: üstü yerel x boyunca ~0.95, y (uygulamada z) boyunca ~0.55.
        let desk = try #require(art.props["desk_set"])
        let xs = stride(from: 0, to: desk.positions.count, by: 3).map { desk.positions[$0] }
        #expect(xs.max()! - xs.min()! > 0.9)
        // Kayalıklar bükülme için z'de sık bölünmüş olmalı: hiçbir üçgen z'de 1 m'den uzun değil.
        for name in ["cliff_a", "cliff_b", "cliff_c"] {
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
        #expect(throws: (any Error).self) { try OfficeArtFile.decode(Data("{\"version\": 2}".utf8)) }
        let badBase64 = Self.sample.replacingOccurrences(of: "\"indices\": \"", with: "\"indices\": \"%%")
        #expect(throws: (any Error).self) { try OfficeArtFile.decode(Data(badBase64.utf8)) }
        // Dizi uzunlukları köşe sayısına uymuyorsa
        let short = Self.sample.replacingOccurrences(of: "\"vertexCount\": 3, \"positions\"", with: "\"vertexCount\": 4, \"positions\"")
        #expect(throws: (any Error).self) { try OfficeArtFile.decode(Data(short.utf8)) }
        // İndeks sınır dışında
        let outOfRange = Self.sample.replacingOccurrences(of: Self.b64([UInt32]([2, 1, 0])), with: Self.b64([UInt32]([2, 1, 7])))
        #expect(throws: (any Error).self) { try OfficeArtFile.decode(Data(outOfRange.utf8)) }
    }
}
