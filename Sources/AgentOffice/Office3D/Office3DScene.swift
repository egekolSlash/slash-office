import AgentOfficeCore
import AppKit
import Metal
import RealityKit

/// Uygulama başına bir kez yüklenen 3D ofis kaynakları (varlıklar, dokular, gökyüzü ışığı).
@MainActor
final class Office3DResources {
    let art: OfficeArt
    let textures: OfficeTextures
    let environment: EnvironmentResource?

    private init(art: OfficeArt, textures: OfficeTextures, environment: EnvironmentResource?) {
        self.art = art
        self.textures = textures
        self.environment = environment
    }

    private static var loading: Task<Office3DResources?, Never>?

    /// Varlıklar bulunamazsa nil: ofis sade görünüme düşer.
    static func shared() async -> Office3DResources? {
        if let loading { return await loading.value }
        let task = Task { @MainActor () -> Office3DResources? in
            guard let art = await OfficeArt.load() else { return nil }
            return Office3DResources(art: art, textures: OfficeTextures(), environment: await OfficeWorld.skyEnvironment())
        }
        loading = task
        return await task.value
    }
}

/// Bir ofis görünümünün 3D sahnesi (spec §6): dünya + köylüler + ortografik kamera, `RealityRenderer` ile çizilir.
@MainActor
final class Office3DScene {
    let camera = OfficeCamera()
    let resources: Office3DResources
    private let renderer: RealityRenderer
    private let world: OfficeWorld
    private let avatars: AvatarController
    private let cameraEntity = Entity()
    private var configured = false
    var lastInteraction = Date.distantPast

    init?(resources: Office3DResources) {
        guard let renderer = try? RealityRenderer() else { return nil }
        self.resources = resources
        self.renderer = renderer
        world = OfficeWorld(art: resources.art, textures: resources.textures)
        let appearance = AvatarAppearance(template: resources.art.villager, textures: resources.textures)
        avatars = AvatarController(art: resources.art, appearance: appearance)
        var ortho = OrthographicCameraComponent()
        ortho.scaleDirection = .vertical
        cameraEntity.components.set(ortho)
        renderer.entities.append(contentsOf: [world.root, avatars.root, cameraEntity])
        renderer.activeCamera = cameraEntity
        renderer.lighting.resource = resources.environment
        renderer.lighting.intensityExponent = -0.6
        renderer.cameraSettings.colorBackground = .color(CGColor(red: 0.62, green: 0.82, blue: 1.0, alpha: 1))
    }

    /// Hareket var mı: yürüyen köylü, kameranın yumuşak geçişi ya da yeni bir jest (kare hızı için).
    var wantsFastFrames: Bool {
        avatars.isMoving || camera.target != nil || Date().timeIntervalSince(lastInteraction) < 0.5
    }

    /// İlk çağrıda köylüler yerinde başlar; sonrakiler canlı değişikliktir (yürürler).
    func update(plan: OfficePlan, desks: [String: OfficeDeskInfo], look: (String) -> AvatarLook,
                style: (String) -> RoomStyle) {
        let color: (String) -> AvatarLook.RGBA = { key in
            let c = ProjectPalette.colors[ProjectPalette.index(for: key)]
            return (c.red, c.green, c.blue)
        }
        world.update(plan: plan, desks: desks, style: style, projectColor: color)
        avatars.sync(plan: plan, desks: desks, look: look, projectColor: color, live: configured)
        configured = true
    }

    /// Bir kare: kamera ve köylüler ilerler, sahne `texture`'a çizilir; GPU bitince `completion`.
    func renderFrame(to texture: MTLTexture, dt: Double, completion: @escaping @Sendable () -> Void) throws {
        camera.step()
        avatars.tick(dt: dt)
        let viewport = camera.viewport
        let t = viewport.cameraTarget()
        let target = SIMD3<Float>(Float(t.x), Float(t.y), Float(t.z))
        let d = OfficeViewport.cameraDirection
        cameraEntity.look(at: target, from: target + SIMD3<Float>(Float(d.x), Float(d.y), Float(d.z)) * 30, relativeTo: nil)
        if var ortho = cameraEntity.components[OrthographicCameraComponent.self] {
            ortho.scale = Float(viewport.orthographicScale(viewHeight: camera.viewSize.height))
            cameraEntity.components.set(ortho)
        }
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        try renderer.updateAndRender(deltaTime: dt, cameraOutput: output, onComplete: { _ in completion() })
    }
}
