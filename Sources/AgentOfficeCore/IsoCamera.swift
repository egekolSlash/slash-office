import simd

/// Ofisin sabit ortografik izometrik kamerası. Sahne kurulumu ve SwiftUI etiketlerinin konumu aynı tanımı kullanır.
public struct IsoCamera: Equatable, Sendable {
    /// Kameranın baktığı noktadan kameraya doğru yön.
    public static let direction = simd_normalize(SIMD3<Float>(1, 1, 1))
    /// Ekranda sağ ve yukarı yönlerin dünya karşılıkları (dünya yukarısı +y ile `look(at:from:)` kuralı).
    public static let screenRight = simd_normalize(simd_cross(-direction, SIMD3<Float>(0, 1, 0)))
    public static let screenUp = simd_normalize(simd_cross(screenRight, -direction))

    public var center: SIMD3<Float>
    /// Görünür yüksekliğin yarısı (dünya birimi), `OrthographicCameraComponent.scale` ile aynı.
    public var scale: Float

    public init(center: SIMD3<Float>, scale: Float) {
        self.center = center
        self.scale = scale
    }

    public var eye: SIMD3<Float> { center + Self.direction * 10 }

    /// İzometrik izdüşümde ızgaranın ekrandaki yüksekliği yaklaşık (w+d)·0.41 + etiketler, genişliği (w+d)·0.71;
    /// ikisinden büyük olanı pencereye sığdırılır.
    public static func fitting(columns: Int, rows: Int, tileSize: Float) -> IsoCamera {
        let width = Float(max(columns, 1)) * tileSize
        let depth = Float(max(rows, 1)) * tileSize
        let span = width + depth
        let center = SIMD3<Float>((width - tileSize) / 2, 0.3, (depth - tileSize) / 2)
        return IsoCamera(center: center, scale: max((span * 0.41 + 1.4) / 1.6, span * 0.71 / 1.7))
    }

    /// Dünya noktasının görünüm içindeki konumu (sol üst orijin, nokta biriminde).
    public func project(_ point: SIMD3<Float>, viewSize: (width: Double, height: Double)) -> (x: Double, y: Double) {
        let offset = point - center
        let pointsPerUnit = viewSize.height / (2 * Double(scale))
        let x = Double(simd_dot(offset, Self.screenRight)) * pointsPerUnit
        let y = Double(simd_dot(offset, Self.screenUp)) * pointsPerUnit
        return (viewSize.width / 2 + x, viewSize.height / 2 - y)
    }
}
