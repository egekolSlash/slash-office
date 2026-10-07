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

    static func marked(_ markers: [String: [UInt8]]) -> OfficeArtFile {
        var art = Self.art
        for (name, marker) in markers {
            var mesh = art.props[name]!
            mesh.colors = Array((0..<mesh.vertexCount).map { _ in marker }.joined())
            art.props[name] = mesh
        }
        return art
    }

    @Test func emptyPlanShowsMeadowAndLots() {
        let mesh = build(plan([]))
        #expect(!mesh.vertices.isEmpty)
        #expect(mesh.vertices.contains { $0.layer == OfficeTextureLayer.grass })
        #expect(mesh.vertices.contains { $0.layer == OfficeTextureLayer.dirt })   // arsa zemini
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.vertices.count })
    }

    @Test func meadowSurroundsPlanAndLots() {
        let p = plan(sample)
        let grass = build(p).vertices.filter { $0.layer == OfficeTextureLayer.grass && $0.normal.y > 0.9 }
        let minX = grass.map(\.position.x).min()!, maxX = grass.map(\.position.x).max()!
        let minZ = grass.map(\.position.z).min()!, maxZ = grass.map(\.position.z).max()!
        let lotsMaxZ = p.lots.map(\.maxZ).max()!
        #expect(Double(minX) <= p.bounds.minX - 29 && Double(maxX) >= p.bounds.maxX + 29)
        #expect(Double(minZ) <= p.bounds.minZ - 29 && Double(maxZ) >= lotsMaxZ + 29)
    }

    @Test func meadowIsAOneMeterGrid() {
        // Bükülme köşe başına uygulanır: zeminde z'de 1 m'den uzun üçgen olmamalı.
        let mesh = build(plan(sample))
        for t in stride(from: 0, to: mesh.indices.count, by: 3) {
            let v = (0..<3).map { mesh.vertices[Int(mesh.indices[t + $0])] }
            guard v.allSatisfy({ $0.layer == OfficeTextureLayer.grass && $0.normal.y > 0.9 }) else { continue }
            let zs = v.map(\.position.z)
            #expect(zs.max()! - zs.min()! <= 1.0 + 1e-4)
        }
    }

    @Test func loungeFurnitureIsPlacedAtSpots() {
        let p = plan(sample)
        let mesh = build(p, art: Self.marked(["sofa": [5, 5, 5, 0], "water_cooler": [6, 6, 6, 0]]))
        let rooms = p.rooms.count
        #expect(count(mesh, color: [5, 5, 5, 0]) == rooms * Self.art.props["sofa"]!.vertexCount)
        #expect(count(mesh, color: [6, 6, 6, 0]) == rooms * Self.art.props["water_cooler"]!.vertexCount)
    }

    /// Odaların zemini, duvarları ve eşyaları iç mekân olarak işaretli (gece sıcak ışık alır); çayır ve manzara değil.
    @Test func roomGeometryIsMarkedInterior() {
        let p = plan(sample)
        let mesh = build(p)
        let interior = mesh.vertices.filter { $0.part == OfficeVertex.interiorPart }
        #expect(!interior.isEmpty)
        for v in interior {
            let inRoom = p.rooms.contains { $0.rect.insetBy(-0.3).contains(x: Double(v.position.x), z: Double(v.position.z)) }
            #expect(inRoom, "\(v.position)")
        }
        #expect(mesh.vertices.filter { $0.layer == OfficeTextureLayer.grass }.allSatisfy { $0.part == 0 })
        #expect(mesh.vertices.contains { $0.layer != 0 && OfficeTextureLayer.floor(0)...OfficeTextureLayer.floor(2) ~= $0.layer
                                         && $0.part == OfficeVertex.interiorPart })
    }

    @Test func longBoxesAreSplitAlongZ() {
        var mesh = OfficeMesh()
        mesh.appendBox(size: SIMD3(0.1, 1, 3), center: SIMD3(0, 0.5, 0), color: SIMD4(255, 255, 255, 0), layer: 0,
                       uvRepeat: SIMD2(3, 1))
        let zs = Set(mesh.vertices.map { ($0.position.z * 100).rounded() })
        #expect(zs.count >= 7)                         // −1,5 … 1,5, en fazla 0,5 aralıkla
        #expect(mesh.indices.count % 3 == 0 && mesh.indices.allSatisfy { Int($0) < mesh.vertices.count })
        // Kesitler boyunca UV sürekli: x'e bakan yüzde u, z boyunca 0…3.
        let side = mesh.vertices.filter { $0.normal.x > 0.9 }
        #expect(abs(side.map(\.uv.x).max()! - 3) < 1e-5 && abs(side.map(\.uv.x).min()!) < 1e-5)
        for v in side { #expect(abs(v.uv.x - (1.5 - v.position.z)) < 1e-4) }
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

    @Test func verticesStayOnTheMeadow() {
        let p = plan(sample)
        let mesh = build(p)
        let b = OfficeWorldBuilder.meadowRect(p), margin: Float = 0.01
        for v in mesh.vertices {
            #expect(v.position.x >= Float(b.minX) - margin && v.position.x <= Float(b.maxX) + margin)
            #expect(v.position.z >= Float(b.minZ) - margin && v.position.z <= Float(b.maxZ) + margin)
            #expect(v.position.y >= -1 && v.position.y <= 12)
        }
    }

    @Test func indicesAreValidTriangles() {
        let mesh = build(plan(sample))
        #expect(mesh.indices.count % 3 == 0)
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.vertices.count })
    }

    @Test func boxHasSixFacesWithOutwardNormals() {
        var mesh = OfficeMesh()
        mesh.appendBox(size: SIMD3(2, 1, 0.5), center: SIMD3(1, 0.5, 2), color: SIMD4(255, 255, 255, 0), layer: 0, uvRepeat: SIMD2(2, 3))
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

@Suite struct OfficeScenaryTests {
    let art = OfficeWorldBuilderTests.art

    func plan(_ rooms: Int) -> OfficePlan {
        let members = (0..<rooms * 2).map { OfficePlan.Member(id: "r\($0 / 2)d\($0 % 2)", roomKey: "/r\($0 / 2)") }
        return OfficePlan.make(members, slots: OfficePlan.assignSlots(members, previous: [:]))
    }

    func items(_ p: OfficePlan) -> [OfficeWorldBuilder.SceneryItem] {
        OfficeWorldBuilder.scenery(plan: p, site: OfficeWorldBuilder.siteRect(p), art: art)
    }

    @Test(arguments: [0, 1, 4])
    func sceneryStaysOffTheSiteAndPath(rooms: Int) {
        let p = plan(rooms)
        let blocked = p.rooms.map(\.rect) + p.lots
            + [PlanRect(minX: OfficePlan.corridorX, minZ: -1, maxX: OfficePlan.corridorX + OfficePlan.corridorWidth,
                        maxZ: OfficeWorldBuilder.siteRect(p).maxZ)]
        for item in items(p) {
            #expect(!blocked.contains { $0.contains(x: item.x, z: item.z) }, "\(item.name) \(item.x),\(item.z)")
        }
    }

    @Test func groundTreesGrowInClustersWithSpacing() {
        let trees = items(plan(4)).filter { ($0.name == "tree" || $0.name == "tree_b" || $0.name == "cedar") && $0.y < 0.1 }
        #expect(trees.count >= 20)
        for (i, a) in trees.enumerated() {
            for b in trees.dropFirst(i + 1) { #expect(hypot(a.x - b.x, a.z - b.z) >= 1.0) }
        }
        // Kümeler: ağaçların çoğunun 2,5 m içinde bir komşusu var (düz sıra değil).
        let clustered = trees.filter { a in trees.contains { b in b.x != a.x && hypot(a.x - b.x, a.z - b.z) < 2.5 } }
        #expect(Double(clustered.count) >= Double(trees.count) * 0.7)
        #expect(Set(trees.map(\.name)).count >= 2)
    }

    @Test func cliffsFormARidgeBehindTheOfficeWithTreesOnTop() {
        let p = plan(4)
        let site = OfficeWorldBuilder.siteRect(p)
        let all = items(p)
        let cliffs = all.filter { $0.name.hasPrefix("cliff") }
        #expect(cliffs.count >= 4)
        #expect(cliffs.allSatisfy { $0.z < site.minZ - 7 })
        #expect(cliffs.map(\.x).min()! < site.minX && cliffs.map(\.x).max()! > site.maxX)
        #expect(all.contains { !$0.name.hasPrefix("cliff") && $0.y > 0.8 })   // kayalık üstünde ağaç
    }

    @Test func flowersGrowInSameColorClumps() {
        let flowers = items(plan(2)).filter { $0.name == "flower" }
        #expect(flowers.count >= 30)
        let sameColorNeighbor = flowers.filter { a in
            flowers.contains { b in (b.x, b.z) != (a.x, a.z) && b.recolor == a.recolor && hypot(a.x - b.x, a.z - b.z) < 0.8 }
        }
        #expect(Double(sameColorNeighbor.count) >= Double(flowers.count) * 0.7)
    }

    @Test func sceneryIsDeterministic() {
        let a = items(plan(3)), b = items(plan(3))
        #expect(a.map { "\($0.name)\($0.x)\($0.z)" } == b.map { "\($0.name)\($0.x)\($0.z)" })
    }
}
