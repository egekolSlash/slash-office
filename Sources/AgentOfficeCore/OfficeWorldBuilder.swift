import Foundation
import simd

/// Ofis adasının statik mesh'i (v3 spec §3, v4 spec §2): çimen, patika, çit, ağaç ve çiçekler; odalar (zemin, halı,
/// paspas, duvarlar, pencere, dekor) ve masa takımları. Kurallar v3 `OfficeWorld` ile aynıdır; aynı girdi aynı mesh'i verir.
public enum OfficeWorldBuilder {
    static let white = SIMD4<UInt8>(255, 255, 255, 0)
    static let fence = OfficeColor.srgb8((0.98, 0.96, 0.92))
    static let lowWall = OfficeColor.srgb8((0.98, 0.95, 0.88))
    static let trim = OfficeColor.srgb8((0.98, 0.96, 0.90))
    /// Çiçek eşyasının taban rengi (doğrusal) ve dört çiçek rengi.
    static let flowerKey: AvatarLook.RGBA = (1.0, 0.42, 0.48)
    static let flowerColors: [AvatarLook.RGBA] = [(1.0, 0.42, 0.48), (1.0, 0.85, 0.30), (1.0, 1.0, 1.0), (0.70, 0.55, 1.0)]

    public static func build(plan: OfficePlan, terminalDesks: Set<String>, style: (String) -> RoomStyle,
                             projectColor: (String) -> AvatarLook.RGBA, art: OfficeArtFile) -> OfficeMesh {
        var mesh = OfficeMesh()
        guard !plan.rooms.isEmpty else { return mesh }
        buildIsland(plan, art: art, into: &mesh)
        for room in plan.rooms {
            buildRoom(room, style: style(room.key), color: projectColor(room.key), art: art, into: &mesh)
            for desk in room.desks {
                let set = terminalDesks.contains(desk.id) ? "terminal_set" : "desk_set"
                if let prop = art.props[set] { mesh.append(prop, at: SIMD3(Float(desk.x), 0, Float(desk.z))) }
            }
        }
        return mesh
    }

    // MARK: - Ada

    static func buildIsland(_ plan: OfficePlan, art: OfficeArtFile, into mesh: inout OfficeMesh) {
        let b = plan.bounds
        let margin = 1.5
        let minX = b.minX - margin, maxX = b.maxX + margin, minZ = b.minZ - margin, maxZ = b.maxZ + margin
        let w = Float(maxX - minX), d = Float(maxZ - minZ)
        let cx = Float(minX + maxX) / 2, cz = Float(minZ + maxZ) / 2
        mesh.appendBox(size: SIMD3(w, 0.3, d), center: SIMD3(cx, -0.17, cz), color: white,
                       layer: OfficeTextureLayer.grass, uvRepeat: SIMD2(w / 2, d / 2))
        mesh.appendBox(size: SIMD3(w - 0.1, 0.7, d - 0.1), center: SIMD3(cx, -0.62, cz), color: white,
                       layer: OfficeTextureLayer.dirt, uvRepeat: SIMD2(w / 2, 1))
        // Koridor patikası: odaların arasında, adanın ön kenarına kadar.
        let corridor = plan.corridor
        let pathLength = Float(maxZ - corridor.minZ) - 0.2
        mesh.appendBox(size: SIMD3(Float(corridor.maxX - corridor.minX) - 0.3, 0.02, pathLength),
                       center: SIMD3(Float(corridor.minX + corridor.maxX) / 2, -0.01, Float(corridor.minZ) + pathLength / 2),
                       color: white, layer: OfficeTextureLayer.path, uvRepeat: SIMD2(1, pathLength / 1.5))
        // Ön kenarda çit (patikada boşluk).
        var x = minX + 0.3
        while x < maxX - 0.2 {
            if x < corridor.minX || x > corridor.maxX {
                mesh.appendBox(size: SIMD3(0.07, 0.42, 0.07), center: SIMD3(Float(x), 0.19, Float(maxZ) - 0.25),
                               color: fence, layer: OfficeTextureLayer.none)
            }
            x += 0.6
        }
        // Ağaçlar kenar şeridinde, çiçekler boş çimende; sabit tohumla (aynı plan, aynı ada).
        var rng = SeededRandom(seed: StableHash.mixed("\(b.minX),\(b.minZ),\(b.maxX),\(b.maxZ)"))
        func free(_ px: Double, _ pz: Double, pad: Double) -> Bool {
            !plan.rooms.contains { $0.rect.insetBy(-pad).contains(x: px, z: pz) }
                && !(px > corridor.minX - pad && px < corridor.maxX + pad && pz > corridor.minZ - pad)
        }
        let key = OfficeColor.linearToSRGB8(flowerKey)
        var trees: [(Double, Double)] = []
        var flowers = 0
        var pz = minZ + 0.4
        while pz < maxZ - 0.4 {
            var px = minX + 0.4
            while px < maxX - 0.4 {
                let edge = min(px - minX, maxX - px, pz - minZ, maxZ - pz) < 1.1
                let roll = rng.next()
                if edge, roll < 0.18, trees.count < 14, free(px, pz, pad: 0.6),
                   trees.allSatisfy({ hypot($0.0 - px, $0.1 - pz) > 1.7 }), let tree = art.props["tree"] {
                    let s = Float(0.8 + rng.next() * 0.35)
                    mesh.append(tree, at: SIMD3(Float(px), -0.02, Float(pz)), scale: s)
                    trees.append((px, pz))
                } else if roll > 0.86, flowers < 70, free(px, pz, pad: 0.2), let flower = art.props["flower"] {
                    let color = flowerColors[Int(rng.next() * Double(flowerColors.count)) % flowerColors.count]
                    let at = SIMD3(Float(px + rng.next() * 0.3), -0.02, Float(pz + rng.next() * 0.3))
                    mesh.append(flower, at: at, recolor: (key, OfficeColor.linearToSRGB8(color)))
                    flowers += 1
                }
                px += 0.5
            }
            pz += 0.5
        }
    }

    // MARK: - Oda

    static func buildRoom(_ room: OfficePlan.Room, style: RoomStyle, color: AvatarLook.RGBA, art: OfficeArtFile,
                          into mesh: inout OfficeMesh) {
        let x = Float(room.x), z = Float(room.z), w = Float(room.width), d = Float(room.depth)
        let tint = OfficeColor.srgb8(color)
        mesh.appendBox(size: SIMD3(w, 0.06, d), center: SIMD3(x + w / 2, -0.03, z + d / 2), color: white,
                       layer: OfficeTextureLayer.floor(style.floor), uvRepeat: SIMD2(w, d))
        // Halı (proje renginde, desenli) ve kapı paspası.
        let rugW = max(w - 0.9, 0.8), rugD = max(d - 0.9, 0.8)
        mesh.appendBox(size: SIMD3(rugW, 0.012, rugD), center: SIMD3(x + w / 2, 0.006, z + d / 2),
                       color: OfficeColor.srgb8(OfficeColor.towardWhite(color, 0.25)),
                       layer: OfficeTextureLayer.rug(style.rug), uvRepeat: SIMD2(rugW / 1.2, rugD / 1.2))
        let inside = room.doorInside
        mesh.appendBox(size: SIMD3(0.45, 0.014, 0.55), center: SIMD3(Float(inside.x), 0.007, Float(inside.z) - 0.1),
                       color: tint, layer: OfficeTextureLayer.none)
        // Duvarlar: dış kenarda tam boy (lambri + duvar kâğıdı), içeride ve önde alçak.
        // Geçici (Task 4'te yeniden yazılır): arka duvar ve x = room.x duvarı.
        let heights = (z: room.backWallHeight, x: room.side == .left ? OfficePlan.wallHeight : OfficePlan.lowWallHeight)
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
        let doorHalf: Float = 0.32
        let doorZ = Float(room.doorZ)
        // Arka (z = room.z) ve sol (x = room.x) duvarlar.
        wall(alongX: true, from: x - t, to: x + w, at: z - t / 2, height: Float(heights.z))
        if room.side == .right {
            // Sağ odaların sol duvarı koridora bakar: kapı boşluğu.
            wall(alongX: false, from: z, to: doorZ - doorHalf, at: x - t / 2, height: Float(heights.x))
            wall(alongX: false, from: doorZ + doorHalf, to: z + d, at: x - t / 2, height: Float(heights.x))
        } else {
            wall(alongX: false, from: z, to: z + d, at: x - t / 2, height: Float(heights.x))
        }
        // Ön alçak duvarlar (z = room.z + d ve x = room.x + w); sol odaların sağ duvarında kapı boşluğu.
        let lowH = Float(OfficePlan.lowWallHeight)
        wall(alongX: true, from: x - t, to: x + w + t, at: z + d + t / 2, height: lowH)
        if room.side == .left {
            wall(alongX: false, from: z, to: doorZ - doorHalf, at: x + w + t / 2, height: lowH)
            wall(alongX: false, from: doorZ + doorHalf, to: z + d, at: x + w + t / 2, height: lowH)
        } else {
            wall(alongX: false, from: z, to: z + d, at: x + w + t / 2, height: lowH)
        }
        // Pencere ve perdeler: tam boy duvarda.
        if heights.z > 1 {
            addWindow(at: SIMD3(x + w / 2, 1.15, z + 0.03), facingZ: true, art: art, into: &mesh)
        } else if heights.x > 1 {
            addWindow(at: SIMD3(x + 0.03, 1.15, z + d / 2), facingZ: false, art: art, into: &mesh)
        }
        addDecor(room: room, tallX: heights.x > 1, art: art, into: &mesh)
    }

    /// Pencere eşyası +x'e bakar; arka (z) duvarda +z'ye bakması için y etrafında −90°.
    static func addWindow(at position: SIMD3<Float>, facingZ: Bool, art: OfficeArtFile, into mesh: inout OfficeMesh) {
        let yaw: Float = facingZ ? -.pi / 2 : 0
        if let window = art.props["window"] { mesh.append(window, at: position, scale: 0.85, yaw: yaw) }
        guard let curtain = art.props["curtain"] else { return }
        for side: Float in [-1, 1] {
            let offset = facingZ ? SIMD3(side * 0.68, 0, 0.03) : SIMD3(0.03, 0, side * 0.68)
            mesh.append(curtain, at: position + offset, yaw: yaw)
        }
    }

    /// Dekor: `room.decorSpots()` noktalarına bitki, lamba, kitaplık. Kitaplık sadece tam boy sol duvarın dibine.
    static func addDecor(room: OfficePlan.Room, tallX: Bool, art: OfficeArtFile, into mesh: inout OfficeMesh) {
        var items = ["plant", "lamp", "bookshelf"]
        for spot in room.spots.map({ PlanPoint(x: $0.x, z: $0.z) }) {
            guard let name = items.first else { break }
            if name == "bookshelf", !(tallX && spot.x - room.x < 0.5) { continue }
            items.removeFirst()
            if let prop = art.props[name] { mesh.append(prop, at: SIMD3(Float(spot.x), 0, Float(spot.z))) }
        }
    }
}
