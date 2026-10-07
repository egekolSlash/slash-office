import Foundation
import simd

/// Ofisin statik mesh'i (v5 spec §3–4): çayır, patika ve meydan, boş arsalar, arka plandaki ağaç sırası ve tepeler,
/// odalar (zemin, halı, paspas, duvarlar, pencere, dinlenme köşesi) ve masa takımları. Aynı girdi aynı mesh'i verir.
public enum OfficeWorldBuilder {
    static let white = SIMD4<UInt8>(255, 255, 255, 0)
    static let post = OfficeColor.srgb8((0.94, 0.91, 0.84))
    static let rope = OfficeColor.srgb8((0.80, 0.67, 0.47))
    static let signBoard = OfficeColor.srgb8((0.77, 0.59, 0.39))
    static let lowWall = OfficeColor.srgb8((0.98, 0.95, 0.88))
    static let trim = OfficeColor.srgb8((0.98, 0.96, 0.90))
    /// Çiçek eşyasının taban rengi (doğrusal) ve dört çiçek rengi.
    static let flowerKey: AvatarLook.RGBA = (1.0, 0.42, 0.48)
    static let flowerColors: [AvatarLook.RGBA] = [(1.0, 0.42, 0.48), (1.0, 0.85, 0.30), (1.0, 1.0, 1.0), (0.70, 0.55, 1.0)]
    /// Çayır, plan ve arsaların her yönde en az bu kadar dışına uzanır; büyük ofiste kamera daha uzaktan baktığı
    /// için ofisin boyu kadar daha.
    static let meadowReach = 30.0
    static let groundY: Float = -0.02

    public static func build(plan: OfficePlan, terminalDesks: Set<String>, style: (String) -> RoomStyle,
                             projectColor: (String) -> AvatarLook.RGBA, art: OfficeArtFile) -> OfficeMesh {
        var mesh = OfficeMesh()
        let site = siteRect(plan)
        mesh.appendGround(rect: meadowRect(plan), height: groundY, cell: 1, color: white,
                          layer: OfficeTextureLayer.grass, uvScale: 0.5)
        buildPath(plan, into: &mesh)
        for lot in plan.lots { buildLot(lot, into: &mesh) }
        buildScenery(plan, site: site, art: art, into: &mesh)
        for room in plan.rooms {
            let start = mesh.vertices.count
            buildRoom(room, style: style(room.key), color: projectColor(room.key), art: art, into: &mesh)
            for desk in room.desks {
                let set = terminalDesks.contains(desk.id) ? "terminal_set" : "desk_set"
                if let prop = art.props[set] { mesh.append(prop, at: SIMD3(Float(desk.x), 0, Float(desk.z))) }
            }
            // Oda içi: gece sıcak oda ışığı alır.
            for i in start..<mesh.vertices.count { mesh.vertices[i].part = OfficeVertex.interiorPart }
        }
        return mesh
    }

    /// Çayırın kapladığı alan.
    public static func meadowRect(_ plan: OfficePlan) -> PlanRect {
        let site = siteRect(plan)
        let reach = min(meadowReach + max(site.maxX - site.minX, site.maxZ - site.minZ), 200)
        return PlanRect(minX: site.minX - reach, minZ: site.minZ - reach, maxX: site.maxX + reach, maxZ: site.maxZ + reach)
    }

    /// Uzak görünümün çerçevesi ve kaydırma sınırı: odaların hepsi, arkada ağaç sırası ve tepelerin eteği, önde
    /// arsaların başı (tabelaları görünsün); boş ofiste bütün alan. Kaydırma odaları, arsaları ve meydanı kaplar.
    public static func fitRect(_ plan: OfficePlan) -> (framed: PlanRect, bounds: PlanRect) {
        let site = siteRect(plan)
        let front = plan.rooms.isEmpty ? site.maxZ
            : max(plan.rooms.map(\.rect.maxZ).max() ?? 0, (plan.lots.map(\.minZ).max() ?? 0) + 3)
        let framed = PlanRect(minX: site.minX - 0.5, minZ: site.minZ - 5, maxX: site.maxX + 0.5, maxZ: min(site.maxZ, front))
        return (framed, PlanRect(minX: framed.minX, minZ: framed.minZ, maxX: framed.maxX, maxZ: site.maxZ))
    }

    /// Odalar, arsalar ve meydanın kapladığı alan.
    public static func siteRect(_ plan: OfficePlan) -> PlanRect {
        var rects = plan.rooms.map(\.rect) + plan.lots
        rects.append(plaza(plan))
        return PlanRect(minX: rects.map(\.minX).min() ?? 0, minZ: min(rects.map(\.minZ).min() ?? 0, 0),
                        maxX: rects.map(\.maxX).max() ?? 0, maxZ: rects.map(\.maxZ).max() ?? 0)
    }

    /// Patikanın bittiği taş meydan: arsaların önünde, koridorun ortasında.
    static func plaza(_ plan: OfficePlan) -> PlanRect {
        let front = plan.lots.map(\.maxZ).max() ?? 0
        let cx = OfficePlan.corridorX + OfficePlan.corridorWidth / 2
        return PlanRect(minX: cx - 2, minZ: front + 0.5, maxX: cx + 2, maxZ: front + 3.5)
    }

    // MARK: - Patika, meydan, arsalar

    static func buildPath(_ plan: OfficePlan, into mesh: inout OfficeMesh) {
        let square = plaza(plan)
        let cx = Float(OfficePlan.corridorX + OfficePlan.corridorWidth / 2)
        let length = Float(square.minZ) + 0.05
        mesh.appendBox(size: SIMD3(Float(OfficePlan.corridorWidth) - 0.3, 0.02, length), center: SIMD3(cx, -0.01, length / 2),
                       color: white, layer: OfficeTextureLayer.path, uvRepeat: SIMD2(1, length / 1.5))
        let w = Float(square.maxX - square.minX), d = Float(square.maxZ - square.minZ)
        mesh.appendBox(size: SIMD3(w, 0.024, d), center: SIMD3(cx, -0.008, Float(square.minZ) + d / 2),
                       color: white, layer: OfficeTextureLayer.path, uvRepeat: SIMD2(w / 1.5, d / 1.5))
        // Meydanın önünde tabela (yazısı kart katmanında).
        let z = Float(square.maxZ) - 0.3
        mesh.appendBox(size: SIMD3(0.07, 0.6, 0.07), center: SIMD3(cx - 0.45, 0.3, z), color: post, layer: 0)
        mesh.appendBox(size: SIMD3(0.07, 0.6, 0.07), center: SIMD3(cx + 0.45, 0.3, z), color: post, layer: 0)
        mesh.appendBox(size: SIMD3(1.3, 0.38, 0.06), center: SIMD3(cx, 0.62, z), color: signBoard, layer: 0)
    }

    /// Boş arsa: toprak zemin, köşelerde direk, ip çit ve "yeni oda" tabelası.
    static func buildLot(_ lot: PlanRect, into mesh: inout OfficeMesh) {
        let w = Float(lot.maxX - lot.minX), d = Float(lot.maxZ - lot.minZ)
        let c = SIMD3(Float(lot.minX + lot.maxX) / 2, Float(-0.012), Float(lot.minZ + lot.maxZ) / 2)
        mesh.appendBox(size: SIMD3(w - 0.3, 0.02, d - 0.3), center: c, color: white, layer: OfficeTextureLayer.dirt,
                       uvRepeat: SIMD2(w / 2, d / 2))
        let inset = 0.15
        for (x, z) in [(lot.minX + inset, lot.minZ + inset), (lot.maxX - inset, lot.minZ + inset),
                       (lot.minX + inset, lot.maxZ - inset), (lot.maxX - inset, lot.maxZ - inset)] {
            mesh.appendBox(size: SIMD3(0.09, 0.4, 0.09), center: SIMD3(Float(x), 0.18, Float(z)), color: post, layer: 0)
        }
        let lenX = w - 2 * Float(inset), lenZ = d - 2 * Float(inset)
        for z in [lot.minZ + inset, lot.maxZ - inset] {
            mesh.appendBox(size: SIMD3(lenX, 0.025, 0.025), center: SIMD3(c.x, 0.3, Float(z)), color: rope, layer: 0)
        }
        for x in [lot.minX + inset, lot.maxX - inset] {
            mesh.appendBox(size: SIMD3(0.025, 0.025, lenZ), center: SIMD3(Float(x), 0.3, c.z), color: rope, layer: 0)
        }
        let z = Float(lot.minZ + OfficePlan.lotSignZ)
        mesh.appendBox(size: SIMD3(0.06, 0.55, 0.06), center: SIMD3(c.x, 0.27, z), color: post, layer: 0)
        mesh.appendBox(size: SIMD3(0.7, 0.34, 0.05), center: SIMD3(c.x, 0.52, z + 0.04), color: signBoard, layer: 0)
    }

    // MARK: - Manzara

    /// Manzaradaki bir eşya: ad (`art.props`), konum, ölçek, y ekseni dönüşü ve (çiçekse) renk sırası.
    public struct SceneryItem: Sendable {
        public var name: String
        public var x: Double, y: Double, z: Double
        public var scale: Double
        public var yaw: Double
        public var recolor: Int?
    }

    static func buildScenery(_ plan: OfficePlan, site: PlanRect, art: OfficeArtFile, into mesh: inout OfficeMesh) {
        let key = OfficeColor.linearToSRGB8(flowerKey)
        for item in scenery(plan: plan, site: site, art: art) {
            guard let prop = art.props[item.name] else { continue }
            let recolor = item.recolor.map { (key, OfficeColor.linearToSRGB8(flowerColors[$0])) }
            mesh.append(prop, at: SIMD3(Float(item.x), Float(item.y), Float(item.z)), scale: Float(item.scale),
                        yaw: Float(item.yaw), recolor: recolor)
        }
    }

    /// AC: New Horizons'tan esinli manzara (v5 spec §3), sabit tohumla:
    /// - arkada iki sıra kademeli kayalık (sırt), ön sıranın tepesinde ağaçlar;
    /// - arkada ve yanlarda kümeler halinde ağaçlar (yuvarlak, ikinci çeşit, sedir karışık);
    /// - boş çimende aynı renkte çiçek öbekleri.
    /// Odalara, arsalara, patikaya ve meydana bir şey konmaz.
    public static func scenery(plan: OfficePlan, site: PlanRect, art: OfficeArtFile) -> [SceneryItem] {
        var rng = SeededRandom(seed: StableHash.mixed("\(site.minX),\(site.minZ),\(site.maxX),\(site.maxZ)"))
        var items: [SceneryItem] = []
        let corridor = PlanRect(minX: OfficePlan.corridorX, minZ: -1, maxX: OfficePlan.corridorX + OfficePlan.corridorWidth,
                                maxZ: site.maxZ)
        let blocked = plan.rooms.map { $0.rect.insetBy(-0.6) } + plan.lots.map { $0.insetBy(-0.4) }
            + [corridor.insetBy(-0.5), plaza(plan).insetBy(-0.5)]
        func free(_ x: Double, _ z: Double) -> Bool { !blocked.contains { $0.contains(x: x, z: z) } }

        // Kayalık sırtı.
        let cliffNames = ["cliff_b", "cliff_a", "cliff_c"].filter { art.props[$0] != nil }
        if !cliffNames.isEmpty {
            for (row, (baseZ, scale)) in [(site.minZ - 10.0, 1.0), (site.minZ - 16.0, 1.35)].enumerated() {
                var x = site.minX - 16 + (row == 1 ? 5 : 0)
                var i = row
                while x < site.maxX + 16 {
                    let name = cliffNames[i % cliffNames.count]
                    let s = scale * (1 + rng.next() * 0.25)
                    let cz = baseZ - rng.next() * 1.5
                    items.append(SceneryItem(name: name, x: x, y: -0.05, z: cz, scale: s, yaw: 0, recolor: nil))
                    // Ön sıranın tepesinde 1–3 ağaç.
                    if row == 0, let top = cliffTop(art.props[name]!) {
                        let count = 1 + Int(rng.next() * 3)
                        for _ in 0..<count {
                            let tx = x + (top.minX + rng.next() * (top.maxX - top.minX)) * s
                            let tz = cz + (top.minZ + rng.next() * (top.maxZ - top.minZ)) * s
                            items.append(SceneryItem(name: rng.next() < 0.6 ? "cedar" : "tree_b", x: tx, y: top.height * s - 0.08,
                                                     z: tz, scale: 0.8 + rng.next() * 0.3, yaw: rng.next() * 2 * .pi, recolor: nil))
                        }
                    }
                    x += (9 + rng.next() * 3) * s
                    i += 1
                }
            }
        }

        // Ağaç kümeleri: arkada bir bant, yanlarda iki şerit.
        var trees: [(Double, Double)] = []
        let species = ["tree", "tree_b", "cedar"].filter { art.props[$0] != nil }
        func cluster(_ cx: Double, _ cz: Double) {
            guard !species.isEmpty else { return }
            let main = species[Int(rng.next() * Double(species.count)) % species.count]
            for _ in 0..<(3 + Int(rng.next() * 3)) {
                let a = rng.next() * 2 * .pi, r = rng.next() * 1.8
                let x = cx + cos(a) * r, z = cz + sin(a) * r
                guard free(x, z), trees.allSatisfy({ hypot($0.0 - x, $0.1 - z) >= 1.1 }) else { continue }
                let name = rng.next() < 0.7 ? main : species[Int(rng.next() * Double(species.count)) % species.count]
                items.append(SceneryItem(name: name, x: x, y: -0.02, z: z, scale: 0.85 + rng.next() * 0.4,
                                         yaw: rng.next() * 2 * .pi, recolor: nil))
                trees.append((x, z))
            }
        }
        var x = site.minX - 12
        while x < site.maxX + 12 {
            cluster(x + rng.next() * 1.5, site.minZ - 3.5 - rng.next() * 2)
            x += 4 + rng.next() * 2.5
        }
        var z = site.minZ
        while z < site.maxZ + 4 {
            cluster(site.minX - 3.5 - rng.next() * 4, z + rng.next() * 2)
            cluster(site.maxX + 3.5 + rng.next() * 4, z + 2.5 + rng.next() * 2)
            z += 5 + rng.next() * 2
        }

        // Çiçek öbekleri.
        if art.props["flower"] != nil {
            var flowers: [(Double, Double)] = []
            for _ in 0..<16 {
                let cx = site.minX - 7 + rng.next() * (site.maxX - site.minX + 14)
                let cz = site.minZ - 4 + rng.next() * (site.maxZ - site.minZ + 9)
                let color = Int(rng.next() * Double(flowerColors.count)) % flowerColors.count
                for _ in 0..<(4 + Int(rng.next() * 4)) {
                    let fx = cx + (rng.next() - 0.5) * 1.2, fz = cz + (rng.next() - 0.5) * 1.2
                    guard free(fx, fz), flowers.allSatisfy({ hypot($0.0 - fx, $0.1 - fz) >= 0.22 }),
                          trees.allSatisfy({ hypot($0.0 - fx, $0.1 - fz) >= 0.6 }) else { continue }
                    items.append(SceneryItem(name: "flower", x: fx, y: -0.02, z: fz, scale: 1, yaw: 0, recolor: color))
                    flowers.append((fx, fz))
                }
            }
        }
        return items
    }

    /// Kayalığın en üst katının yerel ayak izi ve yüksekliği (ağaçlar buraya konur), kenarlardan 0,4 m içeride.
    static func cliffTop(_ mesh: ArtMesh) -> (minX: Double, maxX: Double, minZ: Double, maxZ: Double, height: Double)? {
        let ys = stride(from: 1, to: mesh.positions.count, by: 3).map { Double(mesh.positions[$0]) }
        guard let height = ys.max(), height > 0 else { return nil }
        var minX = Double.infinity, maxX = -Double.infinity, minZ = Double.infinity, maxZ = -Double.infinity
        for i in 0..<mesh.vertexCount where Double(mesh.positions[3 * i + 1]) > height - 0.01 {
            minX = min(minX, Double(mesh.positions[3 * i])); maxX = max(maxX, Double(mesh.positions[3 * i]))
            minZ = min(minZ, Double(mesh.positions[3 * i + 2])); maxZ = max(maxZ, Double(mesh.positions[3 * i + 2]))
        }
        guard maxX - minX > 0.8, maxZ - minZ > 0.8 else { return nil }
        return (minX + 0.4, maxX - 0.4, minZ + 0.4, maxZ - 0.4, height)
    }

    // MARK: - Oda

    static func buildRoom(_ room: OfficePlan.Room, style: RoomStyle, color: AvatarLook.RGBA, art: OfficeArtFile,
                          into mesh: inout OfficeMesh) {
        let x = Float(room.x), z = Float(room.z), w = Float(room.width), d = Float(room.depth)
        let tint = OfficeColor.srgb8(color)
        mesh.appendBox(size: SIMD3(w, 0.06, d), center: SIMD3(x + w / 2, -0.03, z + d / 2), color: white,
                       layer: OfficeTextureLayer.floor(style.floor), uvRepeat: SIMD2(w, d))
        // Halı masa alanında (proje renginde, desenli); kapının içinde paspas.
        let rugW = max(w - 1.0, 0.8), rugD: Float = 3.0
        mesh.appendBox(size: SIMD3(rugW, 0.012, rugD), center: SIMD3(x + w / 2, 0.006, z + 0.6 + rugD / 2),
                       color: OfficeColor.srgb8(OfficeColor.towardWhite(color, 0.25)),
                       layer: OfficeTextureLayer.rug(style.rug), uvRepeat: SIMD2(rugW / 1.2, rugD / 1.2))
        let inside = room.doorInside
        mesh.appendBox(size: SIMD3(0.5, 0.014, 0.6), center: SIMD3(Float(inside.x), 0.007, Float(inside.z)),
                       color: tint, layer: OfficeTextureLayer.none)
        // Duvarlar: arka (ilk odada) ve dış yan tam boy (lambri + duvar kâğıdı); koridor tarafı ve ön alçak.
        let t: Float = 0.1
        func wall(alongX: Bool, from start: Float, to end: Float, at fixed: Float, height: Float) {
            let length = end - start
            guard length > 0.01 else { return }
            func size(_ h: Float, grow: Float = 0) -> SIMD3<Float> {
                alongX ? SIMD3(length, h, t + grow) : SIMD3(t + grow, h, length)
            }
            func center(_ y: Float) -> SIMD3<Float> {
                alongX ? SIMD3(start + length / 2, y, fixed) : SIMD3(fixed, y, start + length / 2)
            }
            if height > 1 {
                let wainscot: Float = 0.8
                mesh.appendBox(size: size(wainscot), center: center(wainscot / 2), color: white,
                               layer: OfficeTextureLayer.wainscot, uvRepeat: SIMD2(length / 0.8, 1))
                mesh.appendBox(size: size(height - wainscot), center: center(wainscot + (height - wainscot) / 2), color: white,
                               layer: OfficeTextureLayer.wallpaper(style.wallpaper), uvRepeat: SIMD2(length, height - wainscot))
                mesh.appendBox(size: size(0.04, grow: 0.02), center: center(wainscot), color: trim, layer: OfficeTextureLayer.none)
            } else {
                mesh.appendBox(size: size(height), center: center(height / 2), color: lowWall, layer: OfficeTextureLayer.none)
            }
        }
        let tall = Float(OfficePlan.wallHeight), low = Float(OfficePlan.lowWallHeight)
        let outerX = Float(room.corridorEdgeX + room.outward * room.width) + Float(room.outward) * t / 2
        let corridorX = Float(room.corridorEdgeX) - Float(room.outward) * t / 2
        wall(alongX: true, from: x - t, to: x + w + t, at: z - t / 2, height: Float(room.backWallHeight))
        wall(alongX: false, from: z, to: z + d, at: outerX, height: tall)
        let doorZ = Float(room.doorZ), doorHalf: Float = 0.4
        wall(alongX: false, from: z, to: doorZ - doorHalf, at: corridorX, height: low)
        wall(alongX: false, from: doorZ + doorHalf, to: z + d, at: corridorX, height: low)
        wall(alongX: true, from: x - t, to: x + w + t, at: z + d + t / 2, height: low)
        // Pencereler: tam boy arka duvarda ve dış yan duvarda (içe bakar).
        if room.backWallHeight > 1 {
            addWindow(at: SIMD3(x + w / 2, 1.15, z + 0.03), yaw: -.pi / 2, art: art, into: &mesh)
        }
        let sideWindowX = Float(room.corridorEdgeX + room.outward * (room.width - 0.03))
        addWindow(at: SIMD3(sideWindowX, 1.15, z + 2.2), yaw: room.outward < 0 ? 0 : .pi, art: art, into: &mesh)
        // Dinlenme köşesi: eşyalar +x'e bakar; `facing` (0 = +z) için yaw = facing − π/2.
        let props: [RoomSpot.Kind: String] = [.sofa: "sofa", .coffeeTable: "coffee_table", .waterCooler: "water_cooler", .plant: "plant"]
        for spot in room.spots {
            guard let name = props[spot.kind], let prop = art.props[name] else { continue }
            mesh.append(prop, at: SIMD3(Float(spot.x), 0, Float(spot.z)), yaw: Float(spot.facing - .pi / 2))
        }
    }

    /// Pencere eşyası +x'e bakar; `yaw` y ekseni etrafında (−π/2: +z'ye). Perdeler pencerenin iki yanında.
    static func addWindow(at position: SIMD3<Float>, yaw: Float, art: OfficeArtFile, into mesh: inout OfficeMesh) {
        if let window = art.props["window"] { mesh.append(window, at: position, scale: 0.85, yaw: yaw) }
        guard let curtain = art.props["curtain"] else { return }
        // Pencerenin genişliği yerel y (uygulamada z) boyunca; döndürülmüş eksende ±0,68.
        let along = SIMD3(sin(yaw), 0, cos(yaw)), out = SIMD3(cos(yaw), 0, -sin(yaw))
        for side: Float in [-1, 1] {
            mesh.append(curtain, at: position + along * side * 0.68 + out * 0.03, yaw: yaw)
        }
    }
}
