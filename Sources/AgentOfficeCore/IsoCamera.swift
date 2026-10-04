import simd

/// Ofisin sabit ortografik izometrik kamerası. Sahne kurulumu ve SwiftUI etiketlerinin konumu aynı tanımı kullanır.
public struct IsoCamera: Equatable, Sendable {
    /// Kameranın baktığı noktadan kameraya doğru yön.
    public static let direction = simd_normalize(SIMD3<Float>(1, 1, 1))
    /// Ekranda sağ ve yukarı yönlerin dünya karşılıkları (dünya yukarısı +y ile `look(at:from:)` kuralı).
    public static let screenRight = simd_normalize(simd_cross(-direction, SIMD3<Float>(0, 1, 0)))
    public static let screenUp = simd_normalize(simd_cross(screenRight, -direction))

    /// Karo başlığının (SwiftUI etiketi) karonun üstündeki yüksekliği.
    public static let labelHeight: Float = 1.05

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

    /// `project`'in tersi: ekran noktasından geçen görüş ışınının `height` yüksekliğindeki yatay düzlemle kesişimi.
    public func unproject(x: Double, y: Double, viewSize: (width: Double, height: Double), height: Float) -> SIMD3<Float> {
        let unitsPerPoint = 2 * Double(scale) / viewSize.height
        let right = Float((x - viewSize.width / 2) * unitsPerPoint)
        let up = Float((viewSize.height / 2 - y) * unitsPerPoint)
        // Kamera düzlemindeki nokta; ışın -direction yönünde ilerler.
        let onPlane = center + Self.screenRight * right + Self.screenUp * up
        let t = (onPlane.y - height) / Self.direction.y
        return onPlane - Self.direction * t
    }

    /// Ekrandaki tıklamanın denk geldiği karo. Önce masa ve NPC yüksekliğinde, sonra zeminde aranır:
    /// izometrik görünümde öndeki karonun mobilyası arkadaki karonun zeminini örter.
    public func tile(atX x: Double, y: Double, viewSize: (width: Double, height: Double),
                     tiles: [TilePlacement], tileSize: Float, labelBox: (width: Double, height: Double)? = nil) -> String? {
        // Başlıklar karonun yukarısında, ekranda arkadaki karonun alanına düşer; önce başlık kutularına bakılır.
        // Örtüşen kutularda öndeki (ekranda daha aşağıdaki) başlık kazanır.
        if let box = labelBox {
            let hits = tiles.compactMap { tile -> (id: String, y: Double)? in
                let anchor = project([Float(tile.column) * tileSize, Self.labelHeight, Float(tile.row) * tileSize], viewSize: viewSize)
                let inside = abs(x - anchor.x) <= box.width / 2 && abs(y - anchor.y) <= box.height / 2
                return inside ? (tile.id, anchor.y) : nil
            }
            if let front = hits.max(by: { $0.y < $1.y }) { return front.id }
        }
        for height: Float in [0.45, 0.02] {
            let point = unproject(x: x, y: y, viewSize: viewSize, height: height)
            let column = Int((point.x / tileSize).rounded())
            let row = Int((point.z / tileSize).rounded())
            let insideTile = abs(point.x - Float(column) * tileSize) <= tileSize / 2
                && abs(point.z - Float(row) * tileSize) <= tileSize / 2
            if insideTile, let hit = tiles.first(where: { $0.column == column && $0.row == row }) {
                return hit.id
            }
        }
        return nil
    }
}
