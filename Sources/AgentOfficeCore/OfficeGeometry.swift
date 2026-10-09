import Foundation
import simd

/// Metal köşesi (40 bayt; shader'daki köşe tanımıyla aynı sıra). Konum ve normal paketli üç float'tır.
/// Köylü mesh'inde `layer` saç modeli kodunu taşır (köylünün desen katmanı instance'tan gelir).
public struct OfficeVertex: Equatable, Sendable {
    public var px, py, pz: Float
    public var nx, ny, nz: Float
    public var u, v: Float
    /// sRGB RGBA8; A = emissive gücü.
    public var color: SIMD4<UInt8>
    public var layer: UInt16
    public var bone: UInt8
    public var part: UInt8

    public init(position: SIMD3<Float>, normal: SIMD3<Float>, uv: SIMD2<Float>, color: SIMD4<UInt8>,
                layer: UInt16 = 0, bone: UInt8 = 0, part: UInt8 = 0) {
        px = position.x; py = position.y; pz = position.z
        nx = normal.x; ny = normal.y; nz = normal.z
        u = uv.x; v = uv.y
        self.color = color; self.layer = layer; self.bone = bone; self.part = part
    }

    /// Dünya mesh'inde `part`: oda içi geometri (gece sıcak oda ışığı alır). Köylüde 0…4 parça kodlarıdır.
    public static let interiorPart: UInt8 = 5

    public var position: SIMD3<Float> { SIMD3(px, py, pz) }
    public var normal: SIMD3<Float> { SIMD3(nx, ny, nz) }
    public var uv: SIMD2<Float> { SIMD2(u, v) }
}

/// Doku dizisinin katmanları (spec v4 §2). 0 = doku yok (beyaz).
public enum OfficeTextureLayer {
    public static let none: UInt16 = 0
    public static func floor(_ i: Int) -> UInt16 { 1 + UInt16(i % RoomStyle.floorCount) }
    public static func wallpaper(_ i: Int) -> UInt16 { 4 + UInt16(i % RoomStyle.wallpaperCount) }
    public static let wainscot: UInt16 = 9
    public static func rug(_ p: RoomStyle.RugPattern) -> UInt16 { 10 + UInt16(RoomStyle.RugPattern.allCases.firstIndex(of: p)!) }
    public static let grass: UInt16 = 13
    public static let dirt: UInt16 = 14
    public static let path: UInt16 = 15
    public static func shirt(_ p: AvatarLook.ShirtPattern) -> UInt16 { 16 + UInt16(AvatarLook.ShirtPattern.allCases.firstIndex(of: p)!) }
    public static let count = 19
}

/// sRGB 8 bit renk yardımcıları.
public enum OfficeColor {
    public static func srgb8(_ c: AvatarLook.RGBA, emissive: UInt8 = 0) -> SIMD4<UInt8> {
        func b(_ x: Double) -> UInt8 { UInt8((min(max(x, 0), 1) * 255).rounded()) }
        return SIMD4(b(c.red), b(c.green), b(c.blue), emissive)
    }

    /// Doğrusal renk (Blender malzemesi gibi) → sRGB 8 bit.
    public static func linearToSRGB8(_ c: AvatarLook.RGBA) -> SIMD4<UInt8> {
        func f(_ x: Double) -> Double { x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055 }
        return srgb8((f(c.red), f(c.green), f(c.blue)))
    }

    /// `c`'yi `fraction` kadar beyaza karıştırır (NSColor.blended gibi).
    public static func towardWhite(_ c: AvatarLook.RGBA, _ fraction: Double) -> AvatarLook.RGBA {
        (c.red + (1 - c.red) * fraction, c.green + (1 - c.green) * fraction, c.blue + (1 - c.blue) * fraction)
    }
}

/// CPU'da birleştirilen mesh: statik dünya tek tampon olur.
public struct OfficeMesh: Sendable {
    public var vertices: [OfficeVertex] = []
    public var indices: [UInt32] = []

    public init() {}

    /// Zemin bükülmesi köşe başına uygulandığı için kutular z'de en fazla bu uzunlukta parçalara bölünür.
    public static let maxSegmentZ: Float = 0.5

    /// Kutu: altı yüz, dışa bakan normaller. UV her yüzde 0…`uvRepeat` (RealityKit'in doku dönüşümü gibi):
    /// x'e bakan yüzlerde u = z, z'ye bakanlarda u = x, üst/altta (u, v) = (x, z); yan yüzlerde v = y.
    /// z boyunca uzun yüzler `maxSegmentZ`'lik parçalara bölünür (UV parçalar boyunca süreklidir).
    public mutating func appendBox(size: SIMD3<Float>, center: SIMD3<Float>, color: SIMD4<UInt8>, layer: UInt16,
                                   uvRepeat: SIMD2<Float> = SIMD2(1, 1)) {
        let h = size / 2
        let zSegments = max(1, Int((size.z / Self.maxSegmentZ).rounded(.up)))
        // Her yüz: normal, u ekseni, v ekseni (u × v = normal olacak şekilde).
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(1, 0, 0), SIMD3(0, 0, -1), SIMD3(0, 1, 0)),
            (SIMD3(-1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 1, 0)),
            (SIMD3(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0, 1, 0)),
            (SIMD3(0, 0, -1), SIMD3(-1, 0, 0), SIMD3(0, 1, 0)),
            (SIMD3(0, 1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, -1)),
            (SIMD3(0, -1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1)),
        ]
        for (n, uAxis, vAxis) in faces {
            let nu = uAxis.z != 0 ? zSegments : 1, nv = vAxis.z != 0 ? zSegments : 1
            let base = UInt32(vertices.count)
            for j in 0...nv {
                for i in 0...nu {
                    let a = Float(i) / Float(nu), b = Float(j) / Float(nv)
                    let p = center + n * h + uAxis * h * (2 * a - 1) + vAxis * h * (2 * b - 1)
                    vertices.append(OfficeVertex(position: p, normal: n, uv: SIMD2(a * uvRepeat.x, (1 - b) * uvRepeat.y),
                                                 color: color, layer: layer))
                }
            }
            let row = UInt32(nu + 1)
            for j in 0..<UInt32(nv) {
                for i in 0..<UInt32(nu) {
                    let v00 = base + j * row + i
                    indices += [v00, v00 + 1, v00 + row + 1, v00, v00 + row + 1, v00 + row]
                }
            }
        }
    }

    /// Düz zemin ızgarası (y = `height`, yukarı bakar): hücre başına iki üçgen; UV dünya konumundan (`uvScale`).
    public mutating func appendGround(rect: PlanRect, height: Float, cell: Float, color: SIMD4<UInt8>, layer: UInt16,
                                      uvScale: Float) {
        let nx = max(1, Int((Float(rect.maxX - rect.minX) / cell).rounded(.up)))
        let nz = max(1, Int((Float(rect.maxZ - rect.minZ) / cell).rounded(.up)))
        let dx = Float(rect.maxX - rect.minX) / Float(nx), dz = Float(rect.maxZ - rect.minZ) / Float(nz)
        let base = UInt32(vertices.count)
        for j in 0...nz {
            for i in 0...nx {
                let p = SIMD3(Float(rect.minX) + Float(i) * dx, height, Float(rect.minZ) + Float(j) * dz)
                vertices.append(OfficeVertex(position: p, normal: SIMD3(0, 1, 0), uv: SIMD2(p.x, p.z) * uvScale,
                                             color: color, layer: layer))
            }
        }
        let row = UInt32(nx + 1)
        for j in 0..<UInt32(nz) {
            for i in 0..<UInt32(nx) {
                let a = base + j * row + i
                // Yukarı bakan yüz (sağ el kuralı, y yukarı): a → a+row → a+1.
                indices += [a, a + row, a + 1, a + 1, a + row, a + row + 1]
            }
        }
    }

    /// Blender eşyası: tek tip ölçek, y etrafında `yaw` (radyan) döndürme, sonra öteleme.
    /// `recolor`: bu renkteki köşeler (±3) yeni renge boyanır (çiçek renkleri).
    public mutating func append(_ art: ArtMesh, at position: SIMD3<Float>, scale: Float = 1, yaw: Float = 0,
                                recolor: (from: SIMD4<UInt8>, to: SIMD4<UInt8>)? = nil, skinned: Bool = false) {
        let c = cos(yaw), s = sin(yaw)
        func rotate(_ p: SIMD3<Float>) -> SIMD3<Float> { SIMD3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c) }
        let base = UInt32(vertices.count)
        for i in 0..<art.vertexCount {
            let p = SIMD3(art.positions[3 * i], art.positions[3 * i + 1], art.positions[3 * i + 2])
            let n = SIMD3(art.normals[3 * i], art.normals[3 * i + 1], art.normals[3 * i + 2])
            var color = SIMD4(art.colors[4 * i], art.colors[4 * i + 1], art.colors[4 * i + 2], art.colors[4 * i + 3])
            if let recolor, Self.close(color, recolor.from) { color = recolor.to }
            vertices.append(OfficeVertex(position: position + rotate(p) * scale, normal: rotate(n),
                                         uv: SIMD2(art.uvs[2 * i], art.uvs[2 * i + 1]), color: color,
                                         // Köylüde katman = varyant (üst bayt grup, alt bayt değer).
                                         layer: skinned ? UInt16(art.variantGroups[i]) << 8 | UInt16(art.variantValues[i]) : 0,
                                         bone: skinned ? art.bones[i] : 0, part: skinned ? art.parts[i] : 0))
        }
        indices += art.indices.map { $0 + base }
    }

    static func close(_ a: SIMD4<UInt8>, _ b: SIMD4<UInt8>) -> Bool {
        (0..<3).allSatisfy { abs(Int(a[$0]) - Int(b[$0])) <= 3 }
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
