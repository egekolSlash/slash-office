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
        let (framed, bounds) = OfficeWorldBuilder.fitRect(plan)
        self.bounds = bounds
        fitViewport = OfficeViewport.fitting(framed, height: 1.9, viewSize: viewSize,
                                             bendFrom: OfficeWorldBuilder.siteRect(plan).minZ)
        if !userMoved {
            viewport = fitViewport
            target = nil
        } else {
            // Kullanıcı gezindiyse yeri korunur; eğim ve bükülme yeni sığdırmaya göre.
            viewport.fitZoom = fitViewport.fitZoom
            viewport.planMinZ = fitViewport.planMinZ
        }
    }

    /// Son elle kamera hareketi (mini ofisin kendiliğinden odağı bir süre bekler).
    private(set) var lastManualMove: Date?

    /// Takip edilen köylü: kamera onu yürürken de ortalar; elle gezinme ya da sığdırma bırakır.
    private(set) var follow: String?
    private(set) var followZoom = 0.0

    /// Köylüye yaklaşır ve onu takip eder. Takipte kamerayı çizim döngüsü her karede köylünün o karedeki yerine göre
    /// yürütür (`followed(to:)` ile buraya yansır): görünüm gizliyken ya da köylü dururken hiçbir şey çalışmaz.
    /// Köylü sahnede değilse (henüz gelmedi) masasına yaklaşılır, takip edilmez.
    func follow(_ id: String, zoom: Double, fallback: (x: Double, y: Double, z: Double)) {
        let zoom = min(max(zoom, limits.lowerBound), limits.upperBound)
        userMoved = true
        guard CameraFollow.shouldContinue(OfficeSharedScene.shared.position(of: id)) else {
            stopFollowing()
            target = OfficeViewport.focusing(x: fallback.x, y: fallback.y, z: fallback.z, zoom: zoom, fit: fitViewport)
            return
        }
        if follow != id { DebugLog.write("office camera follow \(id)") }
        target = nil
        follow = id
        followZoom = zoom
    }

    /// Çizim döngüsünün takip karesindeki görünüm (köylü konumlarıyla aynı anda gelir).
    func followed(to viewport: OfficeViewport) {
        guard follow != nil else { return }
        self.viewport = viewport
    }

    /// Köylü odadan çıktı: takip, döngünün son görünümünde biter.
    func followEnded(_ id: String, at viewport: OfficeViewport) {
        guard follow == id else { return }
        self.viewport = viewport
        stopFollowing()
    }

    func stopFollowing() {
        if let follow { DebugLog.write("office camera follow ends \(follow)") }
        follow = nil
    }

    func pan(dx: Double, dy: Double) {
        stopFollowing()
        target = nil
        userMoved = true
        lastManualMove = Date()
        viewport.pan(dx: dx, dy: dy, within: bounds)
    }

    func zoom(by factor: Double, anchorX: Double, anchorY: Double) {
        stopFollowing()
        target = nil
        userMoved = true
        lastManualMove = Date()
        viewport.zoom(by: factor, anchorX: anchorX, anchorY: anchorY, viewSize: viewSize, limits: limits, within: bounds)
    }

    /// Bir zemin noktasına yumuşakça yaklaşır.
    func focus(x: Double, z: Double, zoom: Double) {
        stopFollowing()
        userMoved = true
        target = OfficeViewport.focusing(x: x, z: z, zoom: min(max(zoom, limits.lowerBound), limits.upperBound), fit: fitViewport)
    }

    /// Yerden `y` yükseklikteki noktayı (köylünün gövdesi) ekranın ortasına getirerek yaklaşır.
    func focus(x: Double, y: Double, z: Double, zoom: Double) {
        stopFollowing()
        userMoved = true
        target = OfficeViewport.focusing(x: x, y: y, z: z, zoom: min(max(zoom, limits.lowerBound), limits.upperBound),
                                         fit: fitViewport)
    }

    /// Sığdırılmış görünüme yumuşakça döner.
    func resetToFit() {
        stopFollowing()
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
