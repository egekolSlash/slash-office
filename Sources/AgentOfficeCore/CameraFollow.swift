import Foundation

/// Odaklanan kamera köylüyü takip eder: hedef, köylünün o anki yerinde gövdesini ekranın ortasına getirir.
/// Köylü odadan çıkınca takip biter; yerinde dururken hedef değişmez (kamera boşuna ekran hızına çıkmasın).
public enum CameraFollow {
    /// Gövde ortası (balona yer kalsın diye biraz yukarısı), metre.
    public static let seatedBody = 0.55
    public static let standingBody = 0.65

    public static func target(x: Double, z: Double, seated: Bool, zoom: Double, fit: OfficeViewport) -> OfficeViewport {
        OfficeViewport.focusing(x: x, y: seated ? seatedBody : standingBody, z: z, zoom: zoom, fit: fit)
    }

    public static func shouldContinue(_ position: AvatarSim.Position?) -> Bool { position?.inRoom == true }

    /// Takipte her karede (çizim thread'inde, köylünün o karedeki yerine): görünüm hedefe yumuşakça yaklaşır,
    /// yaklaşık 0,3 sn'de; adım kare hızından bağımsız. Köylü ve kamera aynı karede ilerlediği için titreme olmaz.
    /// Yarım noktadan yakınsa hedefe oturur (`arrived`).
    public static func step(_ current: OfficeViewport, toward target: OfficeViewport, dt: Double) -> (viewport: OfficeViewport, arrived: Bool) {
        let t = 1 - pow(0.8, min(max(dt, 0), 0.1) * 24)
        var next = current
        next.targetX += (target.targetX - next.targetX) * t
        next.targetZ += (target.targetZ - next.targetZ) * t
        next.zoom += (target.zoom - next.zoom) * t
        next.fitZoom = target.fitZoom
        next.planMinZ = target.planMinZ
        if !needsUpdate(current: next, next: target) { return (target, true) }
        return (next, false)
    }

    /// Hedef ekranda yarım noktadan fazla kaydıysa güncellenir.
    public static func needsUpdate(current: OfficeViewport, next: OfficeViewport) -> Bool {
        abs(current.targetX - next.targetX) * current.zoom > 0.5 || abs(current.targetZ - next.targetZ) * current.zoom > 0.5
            || abs(current.zoom - next.zoom) > 0.05
    }
}
