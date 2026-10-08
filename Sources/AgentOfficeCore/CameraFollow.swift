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

    /// Hedef ekranda yarım noktadan fazla kaydıysa güncellenir.
    public static func needsUpdate(current: OfficeViewport, next: OfficeViewport) -> Bool {
        abs(current.targetX - next.targetX) * current.zoom > 0.5 || abs(current.targetZ - next.targetZ) * current.zoom > 0.5
            || abs(current.zoom - next.zoom) > 0.05
    }
}
