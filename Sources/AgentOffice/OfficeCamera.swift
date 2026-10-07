import AgentOfficeCore
import Foundation
import Observation

/// Ofis kamerası: o anki görünüm, yumuşak geçiş hedefi ve kullanıcının gezinip gezinmediği.
/// Kullanıcı gezinmediyse plan ya da pencere boyutu değişince görünüm yeniden sığdırılır (spec §5).
@MainActor
@Observable
final class OfficeCamera {
    var viewport = OfficeViewport(targetX: 0, targetZ: 0, zoom: 40, fitZoom: 40, planMinZ: 0)
    var target: OfficeViewport?
    var userMoved = false
    var viewSize: OfficeViewport.ViewSize = (800, 500)
    private(set) var fitViewport = OfficeViewport(targetX: 0, targetZ: 0, zoom: 40, fitZoom: 40, planMinZ: 0)
    /// Kaydırma sınırı (plan + arsalar).
    private(set) var bounds = PlanRect.zero

    var limits: ClosedRange<Double> { OfficeViewport.zoomLimits(fit: fitViewport) }

    func fit(_ plan: OfficePlan) {
        // Arka duvarın üstündeki ağaçlar da görünsün diye plan sınırları biraz genişletilir.
        let b = plan.bounds
        let padded = b.isEmpty ? b : PlanRect(minX: b.minX - 0.8, minZ: b.minZ - 0.8, maxX: b.maxX + 0.8, maxZ: b.maxZ + 0.8)
        bounds = padded
        fitViewport = OfficeViewport.fitting(padded, height: 1.9, viewSize: viewSize)
        if !userMoved {
            viewport = fitViewport
            target = nil
        } else {
            // Kullanıcı gezindiyse yeri korunur; eğim ve bükülme yeni sığdırmaya göre.
            viewport.fitZoom = fitViewport.fitZoom
            viewport.planMinZ = fitViewport.planMinZ
        }
    }

    func pan(dx: Double, dy: Double) {
        target = nil
        userMoved = true
        viewport.pan(dx: dx, dy: dy, within: bounds)
    }

    func zoom(by factor: Double, anchorX: Double, anchorY: Double) {
        target = nil
        userMoved = true
        viewport.zoom(by: factor, anchorX: anchorX, anchorY: anchorY, viewSize: viewSize, limits: limits, within: bounds)
    }

    /// Bir zemin noktasına yumuşakça yaklaşır.
    func focus(x: Double, z: Double, zoom: Double) {
        userMoved = true
        target = OfficeViewport.focusing(x: x, z: z, zoom: min(max(zoom, limits.lowerBound), limits.upperBound), fit: fitViewport)
    }

    /// Sığdırılmış görünüme yumuşakça döner.
    func resetToFit() {
        userMoved = false
        target = fitViewport
    }

    /// Hedefe doğru bir adım (yaklaşık 0,3 sn'de varır). `dt`: kare süresi; adım ekranın yenileme hızından bağımsız
    /// (24 fps'te kare başına %20).
    func step(dt: Double = 1.0 / 24) {
        guard let target else { return }
        let t = 1 - pow(0.8, max(dt, 0) * 24)
        var next = viewport
        next.targetX += (target.targetX - next.targetX) * t
        next.targetZ += (target.targetZ - next.targetZ) * t
        next.zoom += (target.zoom - next.zoom) * t
        next.fitZoom = target.fitZoom
        next.planMinZ = target.planMinZ
        if abs(next.zoom - target.zoom) < 0.05, abs(next.targetX - target.targetX) * next.zoom < 0.5,
           abs(next.targetZ - target.targetZ) * next.zoom < 0.5 {
            next = target
            self.target = nil
        }
        viewport = next
    }
}
