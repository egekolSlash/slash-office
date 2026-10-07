import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct OfficeWorldBuilderTests {
    static let art: OfficeArtFile = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/OfficeArt/office-art.json")
        return try! OfficeArtFile.load(from: url)
    }()

    static let deskMarker: [UInt8] = [7, 7, 7, 0]
    static let terminalMarker: [UInt8] = [9, 9, 9, 0]

    /// Masa ve terminal takımlarının köşeleri tanınabilir renge boyanır.
    static let markedArt: OfficeArtFile = {
        var art = Self.art
        for (name, marker) in [("desk_set", deskMarker), ("terminal_set", terminalMarker)] {
            var mesh = art.props[name]!
            mesh.colors = Array((0..<mesh.vertexCount).map { _ in marker }.joined())
            art.props[name] = mesh
        }
        return art
    }()

    func plan(_ pairs: [(String, String)]) -> OfficePlan {
        let members = pairs.map { OfficePlan.Member(id: $0.0, roomKey: $0.1) }
        return OfficePlan.make(members, slots: OfficePlan.assignSlots(members, previous: [:]))
    }

    func build(_ plan: OfficePlan, terminals: Set<String> = [], art: OfficeArtFile = Self.art) -> OfficeMesh {
        OfficeWorldBuilder.build(plan: plan, terminalDesks: terminals, style: { RoomStyle.default(for: $0) },
                                 projectColor: { _ in (0.4, 0.6, 0.9) }, art: art)
    }

    func count(_ mesh: OfficeMesh, color: [UInt8]) -> Int {
        mesh.vertices.filter { [$0.color.x, $0.color.y, $0.color.z, $0.color.w] == color }.count
    }

    let sample = [("a", "/repo/one"), ("b", "/repo/one"), ("c", "/repo/two"), ("d", "/repo/three")]

    @Test func vertexLayoutMatchesShader() {
        #expect(MemoryLayout<OfficeVertex>.stride == 40)
        #expect(MemoryLayout<OfficeVertex>.offset(of: \.color) == 32)
        #expect(MemoryLayout<OfficeVertex>.offset(of: \.layer) == 36)
        #expect(MemoryLayout<OfficeVertex>.offset(of: \.bone) == 38)
        #expect(MemoryLayout<OfficeVertex>.offset(of: \.part) == 39)
    }

    @Test func textureLayersAreDistinct() {
        var layers: [UInt16] = [OfficeTextureLayer.wainscot, OfficeTextureLayer.grass, OfficeTextureLayer.dirt, OfficeTextureLayer.path]
        layers += (0..<RoomStyle.floorCount).map(OfficeTextureLayer.floor)
        layers += (0..<RoomStyle.wallpaperCount).map(OfficeTextureLayer.wallpaper)
        layers += RoomStyle.RugPattern.allCases.map(OfficeTextureLayer.rug)
        layers += AvatarLook.ShirtPattern.allCases.map(OfficeTextureLayer.shirt)
        #expect(Set(layers).count == layers.count)
        #expect(!layers.contains(OfficeTextureLayer.none))
        #expect(layers.allSatisfy { Int($0) < OfficeTextureLayer.count })
    }

    @Test func buildIsDeterministic() {
        let a = build(plan(sample)), b = build(plan(sample))
        #expect(a.vertices == b.vertices)
        #expect(a.indices == b.indices)
        #expect(!a.vertices.isEmpty)
    }

    @Test func emptyPlanGivesEmptyMesh() {
        let mesh = build(plan([]))
        #expect(mesh.vertices.isEmpty && mesh.indices.isEmpty)
    }

    @Test func everyDeskGetsADeskSet() {
        let p = plan(sample)
        let mesh = build(p, art: Self.markedArt)
        #expect(count(mesh, color: Self.deskMarker) == 4 * Self.art.props["desk_set"]!.vertexCount)
        #expect(count(mesh, color: Self.terminalMarker) == 0)
    }

    @Test func terminalDeskUsesTerminalSet() {
        let mesh = build(plan(sample), terminals: ["c"], art: Self.markedArt)
        #expect(count(mesh, color: Self.deskMarker) == 3 * Self.art.props["desk_set"]!.vertexCount)
        #expect(count(mesh, color: Self.terminalMarker) == Self.art.props["terminal_set"]!.vertexCount)
    }

    @Test func deskSetSitsAtTheDesk() {
        let p = plan(sample)
        let mesh = build(p, art: Self.markedArt)
        let desk = p.rooms[0].desks[0]
        let marked = mesh.vertices.filter { $0.color == SIMD4(7, 7, 7, 0) }
        let near = marked.filter { abs(Double($0.position.x) - desk.x) < 0.6 && abs(Double($0.position.z) - desk.z) < 0.6 }
        #expect(near.count == Self.art.props["desk_set"]!.vertexCount)
    }

    @Test func verticesStayOnTheIsland() {
        let p = plan(sample)
        let mesh = build(p)
        let b = p.bounds, margin: Float = 1.5 + 0.01
        for v in mesh.vertices {
            #expect(v.position.x >= Float(b.minX) - margin && v.position.x <= Float(b.maxX) + margin)
            #expect(v.position.z >= Float(b.minZ) - margin && v.position.z <= Float(b.maxZ) + margin)
            #expect(v.position.y >= -1 && v.position.y <= 3)
        }
    }

    @Test func indicesAreValidTriangles() {
        let mesh = build(plan(sample))
        #expect(mesh.indices.count % 3 == 0)
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.vertices.count })
    }

    @Test func boxHasSixFacesWithOutwardNormals() {
        var mesh = OfficeMesh()
        mesh.appendBox(size: SIMD3(2, 1, 4), center: SIMD3(1, 0.5, 2), color: SIMD4(255, 255, 255, 0), layer: 0, uvRepeat: SIMD2(2, 3))
        #expect(mesh.vertices.count == 24 && mesh.indices.count == 36)
        for v in mesh.vertices {
            let outward = (v.position - SIMD3(1, 0.5, 2)) * v.normal
            #expect(outward.sum() > 0)
            #expect(v.uv.x <= 2 && v.uv.y <= 3)
        }
        // Üçgenler dışa bakar (saat yönünün tersi, sağ el kuralı).
        for t in stride(from: 0, to: mesh.indices.count, by: 3) {
            let a = mesh.vertices[Int(mesh.indices[t])], b = mesh.vertices[Int(mesh.indices[t + 1])], c = mesh.vertices[Int(mesh.indices[t + 2])]
            let n = simd_cross(b.position - a.position, c.position - a.position)
            #expect(simd_dot(n, a.normal) > 0)
        }
    }

    @Test func artMeshIsPlacedWithTransform() {
        var mesh = OfficeMesh()
        let lamp = Self.art.props["lamp"]!
        mesh.append(lamp, at: SIMD3(5, 0, 7), scale: 2, yaw: 0)
        #expect(mesh.vertices.count == lamp.vertexCount)
        #expect(mesh.vertices[0].position == SIMD3(5 + 2 * lamp.positions[0], 2 * lamp.positions[1], 7 + 2 * lamp.positions[2]))
    }
}

import simd
