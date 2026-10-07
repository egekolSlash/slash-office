import Foundation
import simd

/// Ofis kamerası (v5 spec §2): karşıdan (dönüş 0, +z tarafından −z'ye) bakan hafif perspektifli kamera. Uzakta
/// (sığdırılmış) eğim 40°, yaklaştıkça 31°'ye iner ve hedefin arkasındaki zemin ufka doğru bükülür. Metal çizici,
/// SwiftUI kartları ve tıklamalar aynı izdüşümü kullanır.
public struct OfficeViewport: Equatable, Sendable {
    public typealias ViewSize = (width: Double, height: Double)

    /// Kameranın baktığı zemin noktası.
    public var targetX: Double
    public var targetZ: Double
    /// Hedefte metre başına nokta.
    public var zoom: Double
    /// Sığdırılmış görünümün yakınlığı (eğim ve bükülme buna göre).
    public var fitZoom: Double
    /// Planın arka kenarı: uzak görünümde bükülme bunun 1 m arkasından başlar.
    public var planMinZ: Double

    public init(targetX: Double, targetZ: Double, zoom: Double, fitZoom: Double, planMinZ: Double) {
        self.targetX = targetX
        self.targetZ = targetZ
        self.zoom = zoom
        self.fitZoom = fitZoom
        self.planMinZ = planMinZ
    }

    public static let fov = 24.0
    /// Bükülme katsayısı: uzakta (sığdırılmış) ve en yakında.
    public static let farBend = 0.026
    public static let nearBend = 0.05
    public static let farPitch = 40.0
    public static let nearPitch = 31.0
    /// Sığdırma en az bu yakınlıktadır (kartlar ve köylüler okunur kalsın); sığmayan ofiste ön taraf gösterilir.
    public static let minFitZoom = 28.0
    /// Sığdırılmış görünümün en büyük ölçeği; `maxZoom`'dan küçük olduğu için içeri yakınlaştırmaya hep yer kalır.
    public static let maxFitZoom = 200.0
    public static let maxZoom = 260.0
    /// Kaydırma sınırı: hedef planın bu kadar dışına çıkamaz.
    public static let panMargin = 3.0
    static let nearPlane = 0.2
    static let farReach = 250.0

    /// 0 uzak (sığdırılmış), 1 en yakın.
    public var nearness: Double {
        guard fitZoom > 0, Self.maxZoom > fitZoom else { return zoom >= Self.maxZoom ? 1 : 0 }
        return min(max(log(zoom / fitZoom) / log(Self.maxZoom / fitZoom), 0), 1)
    }

    public var pitchDegrees: Double { Self.lerp(Self.farPitch, Self.nearPitch, nearness) }

    /// Zemin bükülmesi: `y' = y − k · max(0, startZ − z)²` (sadece çizim ve izdüşüm; ışık bükülmez).
    /// Uzakta da hafiftir (ufuk az görünür); yakınlaştırmanın başında hızla artar (√t), eğim ise doğrusal kalır.
    public var bend: (startZ: Double, k: Double) {
        let e = nearness.squareRoot()
        return (targetZ - Self.lerp(targetZ - planMinZ + 1, 2.5, e), Self.lerp(Self.farBend, Self.nearBend, e))
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    // MARK: - Kamera uzayı

    /// Kamera tabanı: sağ (1,0,0), yukarı, ileri (kameradan sahneye) ve göz konumu; `focal` nokta cinsinden odak.
    struct Basis {
        var up: SIMD3<Double>
        var forward: SIMD3<Double>
        var eye: SIMD3<Double>
        var focal: Double
        var sinPitch: Double
    }

    func basis(viewHeight: Double) -> Basis {
        let p = pitchDegrees * .pi / 180
        let d = SIMD3(0, sin(p), cos(p))
        let halfTan = tan(Self.fov * .pi / 360)
        let dist = max(viewHeight, 1) / max(zoom, 1e-6) / 2 / halfTan
        return Basis(up: SIMD3(0, cos(p), -sin(p)), forward: -d, eye: SIMD3(targetX, 0, targetZ) + d * dist,
                     focal: max(viewHeight, 1) / 2 / halfTan, sinPitch: sin(p))
    }

    /// Bükülmesiz izdüşüm (sol üst orijin, nokta biriminde).
    public func projectUnbent(x: Double, y: Double, z: Double, viewSize: ViewSize) -> (x: Double, y: Double) {
        let b = basis(viewHeight: viewSize.height)
        let r = SIMD3(x, y, z) - b.eye
        let depth = max(simd_dot(r, b.forward), 1e-6)
        return (viewSize.width / 2 + r.x * b.focal / depth, viewSize.height / 2 - simd_dot(r, b.up) * b.focal / depth)
    }

    /// Dünya noktasının görünümdeki yeri (sol üst orijin, nokta biriminde); bükülme dahil.
    public func project(x: Double, y: Double, z: Double, viewSize: ViewSize) -> (x: Double, y: Double) {
        let bend = bend
        let behind = max(bend.startZ - z, 0)
        return projectUnbent(x: x, y: y - bend.k * behind * behind, z: z, viewSize: viewSize)
    }

    /// `project`'in tersi: görünüm noktasından çıkan ışının `height` yüksekliğindeki yatay düzlemi kestiği yer.
    /// Bükülmeyi saymaz; ofisin bulunduğu alan düz olduğu için orada tamdır.
    public func point(atX x: Double, y: Double, height: Double, viewSize: ViewSize) -> (x: Double, z: Double) {
        let b = basis(viewHeight: viewSize.height)
        let dir = SIMD3((x - viewSize.width / 2) / b.focal, 0, 0) - b.up * ((y - viewSize.height / 2) / b.focal) + b.forward
        guard abs(dir.y) > 1e-9 else { return (b.eye.x, b.eye.z) }
        let t = max((height - b.eye.y) / dir.y, 0)
        let hit = b.eye + dir * t
        return (hit.x, hit.z)
    }

    /// Metal için dünya → kırpma uzayı matrisi (bükülme hariç; shader `bend` ile uygular). z ∈ [0, 1], yakın küçük.
    public func viewProjection(viewSize: ViewSize) -> simd_float4x4 {
        let b = basis(viewHeight: viewSize.height)
        let sx = 2 * b.focal / max(viewSize.width, 1), sy = 2 * b.focal / max(viewSize.height, 1)
        let near = Self.nearPlane, far = simd_length(b.eye - SIMD3(targetX, 0, targetZ)) + Self.farReach
        let a = far / (far - near), c = -near * far / (far - near)
        let f = b.forward, u = b.up, e = b.eye
        let rows: [[Double]] = [
            [sx, 0, 0, -sx * e.x],
            [sy * u.x, sy * u.y, sy * u.z, -sy * simd_dot(u, e)],
            [a * f.x, a * f.y, a * f.z, -a * simd_dot(f, e) + c],
            [f.x, f.y, f.z, -simd_dot(f, e)],
        ]
        return Self.matrix(rows: rows)
    }

    // MARK: - Ufuk

    /// Bükülen zeminin ekranda en yukarı çıktığı z (ufuk): bunun arkasındaki noktalar yere gömülür ve ekranda
    /// tekrar aşağı iner; kartları ve tıklamaları sayılmaz. Bükülme yoksa ya da ufuk çok uzaksa −∞.
    public func horizonZ(viewSize: ViewSize) -> Double {
        let bend = bend
        guard bend.k > 0 else { return -.infinity }
        func screenY(_ z: Double) -> Double {
            let behind = max(bend.startZ - z, 0)
            return projectUnbent(x: targetX, y: -bend.k * behind * behind, z: z, viewSize: viewSize).y
        }
        // Kaba adımla en yukarı noktayı bul, sonra incelt.
        var z = bend.startZ, best = screenY(z)
        while z > bend.startZ - 400 {
            let next = screenY(z - 1)
            if next > best { break }
            best = next
            z -= 1
        }
        guard z > bend.startZ - 400 else { return -.infinity }
        var fine = z + 1
        best = screenY(fine)
        while fine > z - 1 {
            let next = screenY(fine - 0.05)
            if next > best { break }
            best = next
            fine -= 0.05
        }
        return fine
    }

    /// Görünüm noktasından çıkan ışın zemine doğru mu iniyor (gökyüzüne değil).
    public func groundVisible(atX x: Double, y: Double, viewSize: ViewSize) -> Bool {
        let b = basis(viewHeight: viewSize.height)
        let dir = SIMD3((x - viewSize.width / 2) / b.focal, 0, 0) - b.up * ((y - viewSize.height / 2) / b.focal) + b.forward
        return dir.y < -1e-6
    }

    // MARK: - Sığdırma ve gezinme

    /// Dikdörtgeni (zeminden `height` yüksekliğe kadar) görünüme sığdırır; sonuç uzak görünümdür (`nearness` 0).
    /// Sığdırma `minFitZoom`'un altına düşerse yakınlık o olur ve dikdörtgenin ön kenarı alt kenarda durur.
    /// `bendFrom`: bükülmenin uzakta başlayacağı planın arka kenarı (verilmezse dikdörtgeninki).
    public static func fitting(_ rect: PlanRect, height: Double, viewSize: ViewSize, margin: Double = 28,
                               bendFrom: Double? = nil) -> OfficeViewport {
        var v = fittingFrame(rect, height: height, viewSize: viewSize, margin: margin)
        if let bendFrom { v.planMinZ = bendFrom }
        return v
    }

    static func fittingFrame(_ rect: PlanRect, height: Double, viewSize: ViewSize, margin: Double) -> OfficeViewport {
        guard !rect.isEmpty else { return OfficeViewport(targetX: 0, targetZ: 0, zoom: 40, fitZoom: 40, planMinZ: 0) }
        let size = (width: max(viewSize.width, 1), height: max(viewSize.height, 1))
        let m = min(margin, size.width / 4, size.height / 4)
        func centered(_ zoom: Double) -> (OfficeViewport, fits: Bool) {
            var v = OfficeViewport(targetX: (rect.minX + rect.maxX) / 2, targetZ: (rect.minZ + rect.maxZ) / 2,
                                   zoom: zoom, fitZoom: zoom, planMinZ: rect.minZ)
            var box = (minX: 0.0, maxX: 0.0, minY: 0.0, maxY: 0.0)
            for _ in 0..<3 {
                box = v.box(rect, height: height, viewSize: size)
                v.targetX += ((box.minX + box.maxX) / 2 - size.width / 2) / zoom
                v.targetZ += ((box.minY + box.maxY) / 2 - size.height / 2) / (zoom * v.basis(viewHeight: size.height).sinPitch)
            }
            box = v.box(rect, height: height, viewSize: size)
            return (v, box.minX >= m - 0.5 && box.maxX <= size.width - m + 0.5 && box.minY >= m - 0.5 && box.maxY <= size.height - m + 0.5)
        }
        var lo = 1.0, hi = maxFitZoom
        if centered(hi).fits { return centered(hi).0 }
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if centered(mid).fits { lo = mid } else { hi = mid }
        }
        if lo >= minFitZoom { return centered(lo).0 }
        // Sığmıyor: en az yakınlıkta, ön kenar alt kenarda.
        var v = OfficeViewport(targetX: (rect.minX + rect.maxX) / 2, targetZ: rect.maxZ, zoom: minFitZoom,
                               fitZoom: minFitZoom, planMinZ: rect.minZ)
        for _ in 0..<4 {
            let front = v.project(x: v.targetX, y: 0, z: rect.maxZ, viewSize: size)
            v.targetZ += (front.y - (size.height - m)) / (v.zoom * v.basis(viewHeight: size.height).sinPitch)
        }
        return v
    }

    /// Dikdörtgenin köşelerinin (0 ve `height` yüksekliğinde) görünümdeki sınırları.
    func box(_ rect: PlanRect, height: Double, viewSize: ViewSize) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        var box = (minX: Double.infinity, maxX: -Double.infinity, minY: Double.infinity, maxY: -Double.infinity)
        for x in [rect.minX, rect.maxX] {
            for z in [rect.minZ, rect.maxZ] {
                for y in [0, height] {
                    let p = project(x: x, y: y, z: z, viewSize: viewSize)
                    box = (min(box.minX, p.x), max(box.maxX, p.x), min(box.minY, p.y), max(box.maxY, p.y))
                }
            }
        }
        return box
    }

    /// Yakınlaştırma sınırları: sığdırılmış görünümden biraz uzağa, bir masanın ekranı doldurmasına kadar yakına.
    public static func zoomLimits(fit: OfficeViewport) -> ClosedRange<Double> {
        let lower = max(fit.zoom * 0.8, 1)
        return lower...max(lower, maxZoom, fit.zoom)
    }

    /// Belli bir zemin noktasına belli yakınlıkta bakan görünüm (odaklama); eğim ve bükülme `fit`'e göredir.
    public static func focusing(x: Double, z: Double, zoom: Double, fit: OfficeViewport) -> OfficeViewport {
        OfficeViewport(targetX: x, targetZ: z, zoom: zoom, fitZoom: fit.fitZoom, planMinZ: fit.planMinZ)
    }

    /// İçerik parmakla birlikte hareket eder (görünüm noktası cinsinden); hedef planın `panMargin` yakınında kalır.
    public mutating func pan(dx: Double, dy: Double, within bounds: PlanRect) {
        targetX -= dx / zoom
        targetZ -= dy / (zoom * basis(viewHeight: 1).sinPitch)
        clamp(to: bounds)
    }

    /// `anchor`'ın altındaki zemin noktası yerinde kalacak şekilde yakınlaştırır.
    public mutating func zoom(by factor: Double, anchorX: Double, anchorY: Double, viewSize: ViewSize,
                              limits: ClosedRange<Double>, within bounds: PlanRect) {
        let ground = point(atX: anchorX, y: anchorY, height: 0, viewSize: viewSize)
        zoom = min(max(zoom * factor, limits.lowerBound), limits.upperBound)
        for _ in 0..<4 {
            let p = projectUnbent(x: ground.x, y: 0, z: ground.z, viewSize: viewSize)
            targetX += (p.x - anchorX) / zoom
            targetZ += (p.y - anchorY) / (zoom * basis(viewHeight: viewSize.height).sinPitch)
        }
        clamp(to: bounds)
    }

    mutating func clamp(to bounds: PlanRect) {
        guard !bounds.isEmpty else { return }
        targetX = min(max(targetX, bounds.minX - Self.panMargin), bounds.maxX + Self.panMargin)
        targetZ = min(max(targetZ, bounds.minZ - Self.panMargin), bounds.maxZ + Self.panMargin)
    }
}

/// Yakınlığa göre kartlarda ne gösterileceği (spec §5).
public enum OfficeDetail: Equatable, Sendable {
    case far, medium, near

    public static func level(zoom: Double) -> OfficeDetail {
        zoom < 45 ? .far : zoom < 110 ? .medium : .near
    }
}

extension OfficePlan {
    /// Görünümdeki tıklamanın denk geldiği masa: önce karakter ve masa yüksekliğinde, sonra zeminde aranır
    /// (öndeki masanın karakteri ekranda arkadaki masanın zeminini örter).
    public func desk(atViewX x: Double, y: Double, viewport: OfficeViewport, viewSize: OfficeViewport.ViewSize) -> String? {
        for height in [0.9, 0.45, 0] {
            let point = viewport.point(atX: x, y: y, height: height, viewSize: viewSize)
            if let id = desk(atX: point.x, z: point.z) { return id }
        }
        return nil
    }
}

/// Sahnenin üstündeki kart ve `?` balonunun yerleşimi. SwiftUI katmanı çizerken, tıklama testi bulurken
/// aynı değerleri kullanır (katman tıklamaları sahneye bırakır).
public enum OfficeOverlay {
    /// Kart ve balonun asıldığı nokta: masanın üstünde, karakterin başı hizasında.
    public static let anchorHeight = 1.1
    public static let cardOffset = 18.0
    /// Kartın tıklanabilir yaklaşık boyutu (başlık + durum satırı).
    public static let cardSize = (width: 130.0, height: 34.0)

    public static func anchor(_ desk: OfficePlan.Desk, viewport: OfficeViewport,
                              viewSize: OfficeViewport.ViewSize) -> (x: Double, y: Double) {
        viewport.project(x: desk.x, y: anchorHeight, z: desk.z, viewSize: viewSize)
    }

    public static func bubbleSize(zoom: Double) -> Double { max(18, min(zoom * 0.35, 34)) }

    /// Ekranın üst kenarına yakın bant: buradaki kartlar gizlenir (ufuk bölgesinde okunmaz, tıklaması şaşar).
    public static let horizonBand = 0.08

    /// Kart, balon ya da tabela gösterilir mi: noktası ufkun önünde ve üst bandın altında. Katman ve tıklama
    /// testi aynı kuralı kullanır.
    public static func isShown(z: Double, anchorY: Double, horizonZ: Double, viewSize: OfficeViewport.ViewSize) -> Bool {
        anchorY > viewSize.height * horizonBand && z > horizonZ + 0.5
    }

    public static func isShown(z: Double, viewport: OfficeViewport, viewSize: OfficeViewport.ViewSize, anchorY: Double) -> Bool {
        isShown(z: z, anchorY: anchorY, horizonZ: viewport.horizonZ(viewSize: viewSize), viewSize: viewSize)
    }

    public static func bubbleOffset(_ detail: OfficeDetail) -> Double { detail == .far ? 6 : 52 }
}

extension OfficePlan {
    /// Tıklama: önce bekleyenlerin `?` balonu, sonra (uzak seviye değilse) masa kartı, sonra sahnedeki masa.
    /// Örtüşen balon ya da kartlarda öndeki (ekranda daha aşağıdaki) kazanır.
    public func desk(atViewX x: Double, y: Double, viewport: OfficeViewport, viewSize: OfficeViewport.ViewSize,
                     detail: OfficeDetail, waiting: Set<String>) -> String? {
        let horizon = viewport.horizonZ(viewSize: viewSize)
        let desks = rooms.flatMap(\.desks).filter { desk in
            OfficeOverlay.isShown(z: desk.z, anchorY: OfficeOverlay.anchor(desk, viewport: viewport, viewSize: viewSize).y,
                                  horizonZ: horizon, viewSize: viewSize)
        }
        let radius = OfficeOverlay.bubbleSize(zoom: viewport.zoom) / 2
        func front(_ hits: [(id: String, y: Double)]) -> String? { hits.max { $0.y < $1.y }?.id }
        let bubbles = desks.compactMap { desk -> (id: String, y: Double)? in
            guard waiting.contains(desk.id) else { return nil }
            let anchor = OfficeOverlay.anchor(desk, viewport: viewport, viewSize: viewSize)
            let center = anchor.y - OfficeOverlay.bubbleOffset(detail)
            return hypot(x - anchor.x, y - center) <= radius + 4 ? (desk.id, anchor.y) : nil
        }
        if let id = front(bubbles) { return id }
        if detail != .far {
            let cards = desks.compactMap { desk -> (id: String, y: Double)? in
                let anchor = OfficeOverlay.anchor(desk, viewport: viewport, viewSize: viewSize)
                let inside = abs(x - anchor.x) <= OfficeOverlay.cardSize.width / 2
                    && abs(y - (anchor.y - OfficeOverlay.cardOffset)) <= OfficeOverlay.cardSize.height / 2
                return inside ? (desk.id, anchor.y) : nil
            }
            if let id = front(cards) { return id }
        }
        // Sahnedeki masa: ufkun arkasındakiler görünmez, seçilmez.
        guard let id = desk(atViewX: x, y: y, viewport: viewport, viewSize: viewSize),
              desks.contains(where: { $0.id == id }) else { return nil }
        return id
    }
}
extension OfficeViewport {
    public static func lightViewProjection(bounds: PlanRect, height: Double, direction: SIMD3<Double>) -> simd_float4x4 {
        let forward = simd_normalize(direction)
        let worldUp = abs(forward.y) > 0.99 ? SIMD3<Double>(0, 0, 1) : SIMD3<Double>(0, 1, 0)
        let right = simd_normalize(simd_cross(forward, worldUp))
        let up = simd_cross(right, forward)
        var lo = SIMD3<Double>(repeating: .infinity), hi = SIMD3<Double>(repeating: -.infinity)
        for x in [bounds.minX, bounds.maxX] {
            for z in [bounds.minZ, bounds.maxZ] {
                for y in [0.0, height] {
                    let p = SIMD3(x, y, z)
                    let q = SIMD3(simd_dot(p, right), simd_dot(p, up), simd_dot(p, forward))
                    lo = simd_min(lo, q)
                    hi = simd_max(hi, q)
                }
            }
        }
        let pad = 0.05
        lo -= pad; hi += pad
        let sx = 2 / (hi.x - lo.x), sy = 2 / (hi.y - lo.y), sz = 1 / (hi.z - lo.z)
        let rows: [[Double]] = [
            [right.x * sx, right.y * sx, right.z * sx, -(lo.x + hi.x) / 2 * sx],
            [up.x * sy, up.y * sy, up.z * sy, -(lo.y + hi.y) / 2 * sy],
            [forward.x * sz, forward.y * sz, forward.z * sz, -lo.z * sz],
            [0, 0, 0, 1],
        ]
        return matrix(rows: rows)
    }

    static func matrix(rows: [[Double]]) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(Float(rows[0][0]), Float(rows[1][0]), Float(rows[2][0]), Float(rows[3][0])),
            SIMD4<Float>(Float(rows[0][1]), Float(rows[1][1]), Float(rows[2][1]), Float(rows[3][1])),
            SIMD4<Float>(Float(rows[0][2]), Float(rows[1][2]), Float(rows[2][2]), Float(rows[3][2])),
            SIMD4<Float>(Float(rows[0][3]), Float(rows[1][3]), Float(rows[2][3]), Float(rows[3][3]))))
    }
}
