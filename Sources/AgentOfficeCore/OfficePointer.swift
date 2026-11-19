import Foundation

/// Ofis haritasında fare ve trackpad. Trackpad ve Magic Mouse kaydırması (olay fazı olan) haritayı kaydırır,
/// kıstırma yakınlaştırır. Fare tekerleği (fazsız) imlecin altına doğru yakınlaştırır; ⇧ ile kaydırır. ⌘ ile her
/// cihazda yakınlaştırma. Boş yerde sol ya da orta tuşla sürüklemek haritayı tutup kaydırır.
public enum OfficePointer {
    public enum ScrollAction: Equatable, Sendable {
        case pan(dx: Double, dy: Double)
        case zoom(factor: Double)
    }

    /// `gestureDevice`: olayın fazı var (trackpad, Magic Mouse). `precise`: piksel cinsinden delta (satır değil).
    public static func scroll(deltaX: Double, deltaY: Double, precise: Bool, gestureDevice: Bool,
                              command: Bool, shift: Bool) -> ScrollAction {
        let zooms = command || (!gestureDevice && !shift)
        if zooms {
            // Yatay tekerlek (ya da ⇧ ile gelen yatay delta) yakınlaştırmaz.
            return .zoom(factor: exp(deltaY * (precise ? 0.01 : 0.1)))
        }
        let scale = precise ? 1.0 : 10.0
        return .pan(dx: deltaX * scale, dy: deltaY * scale)
    }

    /// Basılı tuş bu kadar (nokta) kaymadan bırakılırsa tıklamadır; kayarsa sürükleme olur ve tıklama sayılmaz.
    public static let dragThreshold = 4.0

    public static func isDrag(fromX: Double, fromY: Double, toX: Double, toY: Double) -> Bool {
        hypot(toX - fromX, toY - fromY) >= dragThreshold
    }
}
