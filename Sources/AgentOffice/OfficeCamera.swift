import AgentOfficeCore
import Foundation
import Observation

/// Ofis kamerası: o anki görünüm, yumuşak geçiş hedefi ve kullanıcının gezinip gezinmediği.
/// Kullanıcı gezinmediyse plan ya da pencere boyutu değişince görünüm yeniden sığdırılır (spec §5).
@MainActor
@Observable
final class OfficeCamera {
    var viewport = OfficeViewport(centerX: 0, centerY: 0, zoom: 40)
    var target: OfficeViewport?
    var userMoved = false
    var viewSize: OfficeViewport.ViewSize = (800, 500)
    private(set) var fitViewport = OfficeViewport(centerX: 0, centerY: 0, zoom: 40)

    var limits: ClosedRange<Double> { OfficeViewport.zoomLimits(fit: fitViewport) }

    func fit(_ plan: OfficePlan) {
        // Ada kenarındaki ağaçlar da görünsün diye plan sınırları biraz genişletilir.
        let b = plan.bounds
        let padded = b.isEmpty ? b : PlanRect(minX: b.minX - 0.8, minZ: b.minZ - 0.8, maxX: b.maxX + 0.8, maxZ: b.maxZ + 0.8)
        fitViewport = OfficeViewport.fitting(padded, height: 1.9, viewSize: viewSize)
        if !userMoved { viewport = fitViewport; target = nil }
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
        next.centerX += (target.centerX - next.centerX) * t
        next.centerY += (target.centerY - next.centerY) * t
        next.zoom += (target.zoom - next.zoom) * t
        if abs(next.zoom - target.zoom) < 0.05, abs(next.centerX - target.centerX) * next.zoom < 0.5,
           abs(next.centerY - target.centerY) * next.zoom < 0.5 {
            next = target
            self.target = nil
        }
        viewport = next
    }
}
