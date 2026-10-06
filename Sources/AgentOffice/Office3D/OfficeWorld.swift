import AgentOfficeCore
import AppKit
import RealityKit

/// Ofis adası (spec §3): plandan çimen, patika, odalar (zemin, duvar, halı, dekor) ve masa takımları kurulur.
/// Fark üzerinden güncellenir: değişmeyen oda ve masa yeniden kurulmaz. Plan koordinatları RealityKit'le aynıdır
/// (x, z zemin; y yukarı). Gökyüzü ışığı çizicinin `lighting`'inden gelir.
@MainActor
final class OfficeWorld {
    let root = Entity()
    private let art: OfficeArt
    private let textures: OfficeTextures
    private let island = Entity()
    private var islandBounds: PlanRect?
    private var rooms: [String: (key: RoomKey, entity: Entity)] = [:]
    private var desks: [String: (key: DeskKey, entity: Entity)] = [:]
    private var flowerTemplates: [Entity] = []

    private struct RoomKey: Equatable {
        var room: OfficePlan.Room
        var style: RoomStyle
        var color: [Double]
    }

    private struct DeskKey: Equatable {
        var desk: OfficePlan.Desk
        var terminal: Bool
    }

    init(art: OfficeArt, textures: OfficeTextures) {
        self.art = art
        self.textures = textures
        root.addChild(island)
        let sun = DirectionalLight()
        sun.light.intensity = 2600
        sun.light.color = NSColor(red: 1.0, green: 0.92, blue: 0.80, alpha: 1)
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 40, depthBias: 3)
        sun.look(at: [3, 0, 3], from: [-2, 9, 8], relativeTo: nil)
        root.addChild(sun)
        flowerTemplates = Self.flowerColors.map { color in
            let flower = art.prop("flower")
            Self.recolor(flower, from: [1.0, 0.42, 0.48], to: color)
            return flower
        }
    }

    /// Gökyüzü renk geçişinden ortam ışığı (IBL).
    static func skyEnvironment() async -> EnvironmentResource? {
        let w = 256, h = 128
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(red: 0.55, green: 0.78, blue: 1.0, alpha: 1), CGColor(red: 0.97, green: 0.95, blue: 0.88, alpha: 1),
                      CGColor(red: 0.45, green: 0.62, blue: 0.35, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: .zero, options: [])
        return try? await EnvironmentResource(equirectangular: ctx.makeImage()!)
    }

    func deskEntity(_ id: String) -> Entity? { desks[id]?.entity }

    func update(plan: OfficePlan, desks deskInfos: [String: OfficeDeskInfo],
                style: (String) -> RoomStyle, projectColor: (String) -> AvatarLook.RGBA) {
        if islandBounds != plan.bounds {
            islandBounds = plan.bounds
            island.children.removeAll()
            if !plan.rooms.isEmpty { buildIsland(plan) }
        }
        let keys = Dictionary(uniqueKeysWithValues: plan.rooms.map { room in
            let c = projectColor(room.key)
            return (room.key, RoomKey(room: room, style: style(room.key), color: [c.red, c.green, c.blue]))
        })
        for (id, entry) in rooms where keys[id] != entry.key {
            entry.entity.removeFromParent()
            rooms[id] = nil
        }
        for room in plan.rooms where rooms[room.key] == nil {
            guard let key = keys[room.key] else { continue }
            let entity = buildRoom(room, style: key.style, color: projectColor(room.key))
            root.addChild(entity)
            rooms[room.key] = (key, entity)
        }
        let placed = Dictionary(uniqueKeysWithValues: plan.rooms.flatMap(\.desks).map { ($0.id, $0) })
        for (id, entry) in desks {
            let key = placed[id].map { DeskKey(desk: $0, terminal: deskInfos[id]?.kind == .shell) }
            if key != entry.key {
                entry.entity.removeFromParent()
                desks[id] = nil
            }
        }
        for (id, desk) in placed where desks[id] == nil {
            let terminal = deskInfos[id]?.kind == .shell
            let entity = art.prop(terminal ? "terminal_set" : "desk_set")
            entity.position = [Float(desk.x), 0, Float(desk.z)]
            root.addChild(entity)
            desks[id] = (DeskKey(desk: desk, terminal: terminal), entity)
        }
    }

    // MARK: - Ada

    private static let flowerColors: [[Double]] = [[1.0, 0.42, 0.48], [1.0, 0.85, 0.30], [1.0, 1.0, 1.0], [0.70, 0.55, 1.0]]

    private func buildIsland(_ plan: OfficePlan) {
        let b = plan.bounds
        let margin = 1.5
        let minX = b.minX - margin, maxX = b.maxX + margin, minZ = b.minZ - margin, maxZ = b.maxZ + margin
        let w = Float(maxX - minX), d = Float(maxZ - minZ)
        let cx = Float(minX + maxX) / 2, cz = Float(minZ + maxZ) / 2
        island.addChild(Self.box([w, 0.3, d], at: [cx, -0.17, cz],
                                 textures.material(textures.grass, repeats: [w / 2, d / 2]), corner: 0.12))
        island.addChild(Self.box([w - 0.1, 0.7, d - 0.1], at: [cx, -0.62, cz],
                                 textures.material(textures.dirt, repeats: [w / 2, 1]), corner: 0.15))
        // Koridor patikası: odaların arasında, adanın ön kenarına kadar.
        let corridor = plan.corridor
        let pathLength = Float(maxZ - corridor.minZ) - 0.2
        island.addChild(Self.box([Float(corridor.maxX - corridor.minX) - 0.3, 0.02, pathLength],
                                 at: [Float(corridor.minX + corridor.maxX) / 2, -0.01, Float(corridor.minZ) + pathLength / 2],
                                 textures.material(textures.path, repeats: [1, pathLength / 1.5])))
        // Ön kenarda çit (patikada boşluk).
        let fence = textures.material(nil, tint: NSColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1), roughness: 0.5)
        var x = minX + 0.3
        while x < maxX - 0.2 {
            if x < corridor.minX || x > corridor.maxX {
                island.addChild(Self.box([0.07, 0.42, 0.07], at: [Float(x), 0.19, Float(maxZ) - 0.25], fence, corner: 0.02))
            }
            x += 0.6
        }
        // Ağaçlar kenar şeridinde, çiçekler boş çimende; sabit tohumla (aynı plan, aynı ada).
        var rng = SeededRandom(seed: StableHash.mixed("\(b.minX),\(b.minZ),\(b.maxX),\(b.maxZ)"))
        func free(_ px: Double, _ pz: Double, pad: Double) -> Bool {
            !plan.rooms.contains { $0.rect.insetBy(-pad).contains(x: px, z: pz) }
                && !(px > corridor.minX - pad && px < corridor.maxX + pad && pz > corridor.minZ - pad)
        }
        var trees: [(Double, Double)] = []
        var flowers = 0
        var pz = minZ + 0.4
        while pz < maxZ - 0.4 {
            var px = minX + 0.4
            while px < maxX - 0.4 {
                let edge = min(px - minX, maxX - px, pz - minZ, maxZ - pz) < 1.1
                let roll = rng.next()
                if edge, roll < 0.18, trees.count < 14, free(px, pz, pad: 0.6),
                   trees.allSatisfy({ hypot($0.0 - px, $0.1 - pz) > 1.7 }) {
                    let tree = art.prop("tree")
                    let s = Float(0.8 + rng.next() * 0.35)
                    tree.scale = [s, s, s]
                    tree.position = [Float(px), -0.02, Float(pz)]
                    island.addChild(tree)
                    trees.append((px, pz))
                } else if roll > 0.86, flowers < 70, free(px, pz, pad: 0.2), !flowerTemplates.isEmpty {
                    let flower = flowerTemplates[Int(rng.next() * Double(flowerTemplates.count)) % flowerTemplates.count].clone(recursive: true)
                    flower.position = [Float(px + rng.next() * 0.3), -0.02, Float(pz + rng.next() * 0.3)]
                    island.addChild(flower)
                    flowers += 1
                }
                px += 0.5
            }
            pz += 0.5
        }
    }

    // MARK: - Oda

    private func buildRoom(_ room: OfficePlan.Room, style: RoomStyle, color: AvatarLook.RGBA) -> Entity {
        let entity = Entity()
        let x = Float(room.x), z = Float(room.z), w = Float(room.width), d = Float(room.depth)
        let tint = OfficeTextures.color(color)
        entity.addChild(Self.box([w, 0.06, d], at: [x + w / 2, -0.03, z + d / 2],
                                 textures.material(textures.floor(style.floor), repeats: [w, d], roughness: 0.6)))
        // Halı (proje renginde, desenli) ve kapı paspası.
        let rugW = max(w - 0.9, 0.8), rugD = max(d - 0.9, 0.8)
        let rugTint = tint.blended(withFraction: 0.25, of: .white) ?? tint
        entity.addChild(Self.box([rugW, 0.012, rugD], at: [x + w / 2, 0.006, z + d / 2],
                                 textures.material(textures.rug(style.rug), tint: rugTint, repeats: [rugW / 1.2, rugD / 1.2], roughness: 0.95),
                                 corner: 0.004))
        let inside = room.doorInside
        entity.addChild(Self.box([0.45, 0.014, 0.55], at: [Float(inside.x), 0.007, Float(inside.z) - 0.1],
                                 textures.material(nil, tint: tint, roughness: 0.9), corner: 0.005))
        // Duvarlar: dış kenarda tam boy (lambri + duvar kâğıdı), içeride ve önde alçak (spec §3).
        let heights = room.backWallHeights
        let wallpaper = textures.wallpaper(style.wallpaper)
        let low = textures.material(nil, tint: NSColor(red: 0.98, green: 0.95, blue: 0.88, alpha: 1), roughness: 0.6)
        let t: Float = 0.1
        func wall(along xAxis: Bool, from start: Float, to end: Float, at fixed: Float, height: Float) {
            let length = end - start
            guard length > 0.01 else { return }
            let size: SIMD3<Float> = xAxis ? [length, 0, t] : [t, 0, length]
            func center(_ y: Float) -> SIMD3<Float> {
                xAxis ? [start + length / 2, y, fixed] : [fixed, y, start + length / 2]
            }
            if height > 1 {
                let wainscot: Float = 0.8
                entity.addChild(Self.box([size.x, wainscot, size.z], at: center(wainscot / 2),
                                         textures.material(textures.wainscot, repeats: [length / 0.8, 1], roughness: 0.6)))
                entity.addChild(Self.box([size.x, height - wainscot, size.z], at: center(wainscot + (height - wainscot) / 2),
                                         textures.material(wallpaper, repeats: [length / 1.0, (height - wainscot) / 1.0], roughness: 0.85)))
                entity.addChild(Self.box([size.x + (xAxis ? 0 : 0.02), 0.04, size.z + (xAxis ? 0.02 : 0)], at: center(wainscot),
                                         textures.material(nil, tint: NSColor(red: 0.98, green: 0.96, blue: 0.9, alpha: 1), roughness: 0.4)))
            } else {
                entity.addChild(Self.box([size.x, height, size.z], at: center(height / 2), low, corner: 0.02))
            }
        }
        let doorHalf: Float = 0.32
        let doorZ = Float(room.doorZ)
        // Arka (z = room.z) ve sol (x = room.x) duvarlar.
        wall(along: true, from: x - t, to: x + w, at: z - t / 2, height: Float(heights.z))
        if room.side == .right {
            // Sağ odaların sol duvarı koridora bakar: kapı boşluğu.
            wall(along: false, from: z, to: doorZ - doorHalf, at: x - t / 2, height: Float(heights.x))
            wall(along: false, from: doorZ + doorHalf, to: z + d, at: x - t / 2, height: Float(heights.x))
        } else {
            wall(along: false, from: z, to: z + d, at: x - t / 2, height: Float(heights.x))
        }
        // Ön alçak duvarlar (z = room.z + d ve x = room.x + w); sol odaların sağ duvarında kapı boşluğu.
        let lowH = Float(OfficePlan.lowWallHeight)
        wall(along: true, from: x - t, to: x + w + t, at: z + d + t / 2, height: lowH)
        if room.side == .left {
            wall(along: false, from: z, to: doorZ - doorHalf, at: x + w + t / 2, height: lowH)
            wall(along: false, from: doorZ + doorHalf, to: z + d, at: x + w + t / 2, height: lowH)
        } else {
            wall(along: false, from: z, to: z + d, at: x + w + t / 2, height: lowH)
        }
        // Pencere ve perdeler: tam boy duvarda.
        if heights.z > 1 {
            addWindow(to: entity, at: [x + w / 2, 1.15, z + 0.03], facingZ: true)
        } else if heights.x > 1 {
            addWindow(to: entity, at: [x + 0.03, 1.15, z + d / 2], facingZ: false)
        }
        addDecor(to: entity, room: room, tallX: heights.x > 1, tallZ: heights.z > 1)
        return entity
    }

    /// Pencere eşyası +x'e bakar; arka (z) duvarda +z'ye bakması için y etrafında −90°.
    private func addWindow(to entity: Entity, at position: SIMD3<Float>, facingZ: Bool) {
        let rotation = facingZ ? simd_quatf(angle: -.pi / 2, axis: [0, 1, 0]) : simd_quatf(angle: 0, axis: [0, 1, 0])
        let window = art.prop("window")
        window.scale = [0.85, 0.85, 0.85]
        window.position = position
        window.orientation = rotation
        entity.addChild(window)
        for side: Float in [-1, 1] {
            let curtain = art.prop("curtain")
            curtain.orientation = rotation
            curtain.position = position + (facingZ ? [side * 0.68, 0.0, 0.03] : [0.03, 0.0, side * 0.68])
            entity.addChild(curtain)
        }
    }

    /// Dekor: masa olmayan karelere (şeritten uzak, duvar dibine) bitki, lamba, kitaplık.
    private func addDecor(to entity: Entity, room: OfficePlan.Room, tallX: Bool, tallZ: Bool) {
        var occupied = Set<String>()
        for desk in room.desks {
            occupied.insert("\(Int(desk.x - room.x)),\(Int(desk.z - room.z))")
        }
        let laneColumn = room.width % 2 == 1 ? room.width / 2 : -1
        var free: [(i: Int, j: Int)] = []
        for j in 0..<room.depth {
            for i in 0..<room.width where i != laneColumn && !occupied.contains("\(i),\(j)") {
                // Ön şerit kapı ve yürüme yolu: son sıranın ön yarısına dekor konmaz, sadece duvar dibine.
                free.append((i, j))
            }
        }
        let items = ["plant", "lamp", "bookshelf"]
        for (index, cell) in free.prefix(items.count).enumerated() {
            let name = items[index]
            if name == "bookshelf", !(tallX && cell.i == 0) { continue }
            let prop = art.prop(name)
            // Hücrenin duvara (sol ya da arka) ya da şerit dışı kenarına yakın köşesi.
            let px = room.x + Double(cell.i) + (cell.i == 0 ? 0.22 : 0.78)
            let pz = room.z + Double(cell.j) + (cell.j == 0 ? 0.25 : 0.5)
            prop.position = [Float(px), 0, Float(pz)]
            entity.addChild(prop)
        }
    }

    // MARK: - Yardımcılar

    static func box(_ size: SIMD3<Float>, at position: SIMD3<Float>, _ material: PhysicallyBasedMaterial, corner: Float = 0.01) -> ModelEntity {
        let mesh = MeshResource.generateBox(width: size.x, height: size.y, depth: size.z,
                                            cornerRadius: min(corner, min(size.x, size.y, size.z) / 2.1), splitFaces: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = position
        return entity
    }

    /// Taban rengi `from` olan malzemeleri `to` rengine çevirir (USD'den doğrusal değerler gelir).
    static func recolor(_ entity: Entity, from: [Double], to: [Double]) {
        if var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { material in
                guard var pbr = material as? PhysicallyBasedMaterial,
                      let c = pbr.baseColor.tint.cgColor.components, c.count >= 3,
                      zip(c.prefix(3).map(Double.init), from).allSatisfy({ abs($0 - $1) < 0.02 }) else { return material }
                pbr.baseColor.tint = OfficeTextures.linearColor((to[0], to[1], to[2]))
                return pbr
            }
            entity.components.set(model)
        }
        entity.children.forEach { recolor($0, from: from, to: to) }
    }
}

/// Sabit tohumlu basit üreteç (PCG tarzı LCG): aynı plan aynı adayı verir.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed | 1 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

extension PlanRect {
    /// Negatif değer dikdörtgeni büyütür.
    func insetBy(_ amount: Double) -> PlanRect {
        PlanRect(minX: minX + amount, minZ: minZ + amount, maxX: maxX - amount, maxZ: maxZ - amount)
    }
}
