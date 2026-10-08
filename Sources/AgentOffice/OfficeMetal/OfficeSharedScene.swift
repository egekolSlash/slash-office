import AgentOfficeCore
import Foundation

/// Ofis modu ve mini ofis arasında paylaşılan sahne durumu: köylü simülasyonu, saat ve kurulmuş dünya mesh'i.
/// Mod değişince yeni görünüm sıfırdan başlamaz: köylüler kaldıkları yerden devam eder, dünya yeniden kurulmaz.
/// Ana thread durumu uygular, çizim thread'leri ilerletir ve okur; hepsi kilit altında.
final class OfficeSharedScene: @unchecked Sendable {
    static let shared = OfficeSharedScene()

    struct Frame {
        var instances: [AvatarInstance]
        var time: Double
        /// Yürüyen köylü (native kare hızı).
        var moving: Bool
        /// Yerinde hareket ya da klip geçişi (30 fps).
        var acting: Bool
    }

    private let lock = NSLock()
    private var sim: AvatarSim?
    private var lastScene: OfficeSceneInput?
    private var synced = false
    private var clock = 0.0
    private var lastTick: Double?
    private var world: (key: OfficeWorldKey, mesh: OfficeMesh, site: PlanRect)?

    /// Yeni sahne girdisi: ilk kez yerinde başlar, sonrası canlıdır (köylüler yürür).
    func apply(_ scene: OfficeSceneInput, skeleton: VillagerSkeleton) {
        lock.lock(); defer { lock.unlock() }
        if sim == nil { sim = AvatarSim(skeleton: skeleton) }
        guard scene != lastScene else { return }
        lastScene = scene
        sim?.sync(plan: scene.plan, desks: scene.desks, looks: scene.looks, projectColors: scene.projectColors, live: synced)
        synced = true
    }

    /// Simülasyonu duvar saatine göre ilerletir (iki görünüm birden çizse de bir kez) ve kare için anlık durumu verir.
    func advance(now: Double) -> Frame {
        lock.lock(); defer { lock.unlock() }
        let dt = lastTick.map { min(max(now - $0, 0), 0.1) } ?? 0
        lastTick = now
        clock += dt
        if dt > 0 { sim?.tick(dt: dt) }
        return frame()
    }

    /// Bütün köylülerin yerleri (kartlar, tıklama; ana thread).
    func positions() -> [String: AvatarSim.Position] {
        lock.lock(); defer { lock.unlock() }
        return sim?.positions ?? [:]
    }

    /// Köylünün o anki yeri (kamera takibi, ana thread).
    func position(of id: String) -> AvatarSim.Position? {
        lock.lock(); defer { lock.unlock() }
        return sim?.position(of: id)
    }

    /// İlerletmeden anlık durum (kare hızı kararı için).
    func peek() -> Frame {
        lock.lock(); defer { lock.unlock() }
        return frame()
    }

    private func frame() -> Frame {
        let instances = sim?.instances ?? []
        return Frame(instances: instances, time: clock, moving: sim?.isWalking ?? false,
                     acting: (sim?.isActing ?? false) || instances.contains { $0.blend < 1 })
    }

    func cachedWorld(for key: OfficeWorldKey) -> (mesh: OfficeMesh, site: PlanRect)? {
        lock.lock(); defer { lock.unlock() }
        guard let world, world.key == key else { return nil }
        return (world.mesh, world.site)
    }

    func store(world mesh: OfficeMesh, site: PlanRect, for key: OfficeWorldKey) {
        lock.lock(); defer { lock.unlock() }
        world = (key, mesh, site)
    }
}
