import Foundation

/// Ofisin izometrik görünümü (spec §5). Sprite sahnesi, SwiftUI kartları ve tıklamalar aynı izdüşümü kullanır.
/// Ekran düzlemi: kamera (1,1,1) yönünden bakar; sx = (x − z)/√2, sy = (2y − x − z)/√6 (sy yukarı).
public struct OfficeViewport: Equatable, Sendable {
    public typealias ViewSize = (width: Double, height: Double)
    static let root2 = 2.0.squareRoot()
    static let root6 = 6.0.squareRoot()

    /// Görünümün ortasına denk gelen ekran düzlemi noktası.
    public var centerX: Double
    public var centerY: Double
    /// Bir dünya biriminin (karonun) ekran düzlemindeki nokta karşılığı.
    public var zoom: Double

    public init(centerX: Double, centerY: Double, zoom: Double) {
        self.centerX = centerX
        self.centerY = centerY
        self.zoom = zoom
    }

    public static func screenPlane(x: Double, y: Double, z: Double) -> (x: Double, y: Double) {
        ((x - z) / root2, (2 * y - x - z) / root6)
    }

    /// Dünya noktasının görünümdeki yeri (sol üst orijin, nokta biriminde).
    public func project(x: Double, y: Double, z: Double, viewSize: ViewSize) -> (x: Double, y: Double) {
        let plane = Self.screenPlane(x: x, y: y, z: z)
        return (viewSize.width / 2 + (plane.x - centerX) * zoom, viewSize.height / 2 - (plane.y - centerY) * zoom)
    }

    /// `project`'in tersi: görünüm noktasının `height` yüksekliğindeki yatay düzlemde denk geldiği yer.
    public func point(atX x: Double, y: Double, height: Double, viewSize: ViewSize) -> (x: Double, z: Double) {
        let sx = centerX + (x - viewSize.width / 2) / zoom
        let sy = centerY - (y - viewSize.height / 2) / zoom
        let difference = sx * Self.root2
        let sum = 2 * height - sy * Self.root6
        return ((sum + difference) / 2, (sum - difference) / 2)
    }

    /// Dikdörtgeni (zeminden `height` yüksekliğe kadar) görünüme sığdırır.
    public static func fitting(_ rect: PlanRect, height: Double, viewSize: ViewSize, margin: Double = 28) -> OfficeViewport {
        guard !rect.isEmpty else { return OfficeViewport(centerX: 0, centerY: 0, zoom: 40) }
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        for x in [rect.minX, rect.maxX] {
            for z in [rect.minZ, rect.maxZ] {
                for y in [0, height] {
                    let p = screenPlane(x: x, y: y, z: z)
                    minX = min(minX, p.x)
                    maxX = max(maxX, p.x)
                    minY = min(minY, p.y)
                    maxY = max(maxY, p.y)
                }
            }
        }
        let usableWidth = max(viewSize.width - 2 * margin, 1)
        let usableHeight = max(viewSize.height - 2 * margin, 1)
        let zoom = max(min(usableWidth / (maxX - minX), usableHeight / (maxY - minY)), 1)
        return OfficeViewport(centerX: (minX + maxX) / 2, centerY: (minY + maxY) / 2, zoom: zoom)
    }

    /// Yakınlaştırma sınırları: sığdırılmış görünümden biraz uzağa, bir masanın ekranı doldurmasına kadar yakına.
    public static func zoomLimits(fit: OfficeViewport) -> ClosedRange<Double> {
        let lower = max(fit.zoom * 0.8, 1)
        return lower...max(lower, 260)
    }

    /// İçerik parmakla birlikte hareket eder (görünüm noktası cinsinden).
    public mutating func pan(dx: Double, dy: Double) {
        centerX -= dx / zoom
        centerY += dy / zoom
    }

    /// `anchor`'daki nokta yerinde kalacak şekilde yakınlaştırır.
    public mutating func zoom(by factor: Double, anchorX: Double, anchorY: Double, viewSize: ViewSize,
                              limits: ClosedRange<Double>) {
        let planeX = centerX + (anchorX - viewSize.width / 2) / zoom
        let planeY = centerY - (anchorY - viewSize.height / 2) / zoom
        zoom = min(max(zoom * factor, limits.lowerBound), limits.upperBound)
        centerX = planeX - (anchorX - viewSize.width / 2) / zoom
        centerY = planeY + (anchorY - viewSize.height / 2) / zoom
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
