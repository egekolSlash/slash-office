import AgentOfficeCore
import AppKit
import Metal
import QuartzCore
import SwiftUI

/// Köylü özelleştirme önizlemesi (ofis hayatı §C4): tek köylü küçük bir zeminde, sırayla ayakta hareketler yapar
/// (`PreviewClips`). Ofisin çizicisi kullanılır; 30 fps, pencere görünmüyorken çizmez. Sürükleyince döner.
struct VillagerPreview: NSViewRepresentable {
    var look: AvatarLook
    var shirtColor: AvatarLook.RGBA

    func makeNSView(context: Context) -> VillagerPreviewNSView { VillagerPreviewNSView() }

    func updateNSView(_ view: VillagerPreviewNSView, context: Context) {
        view.update(look: look, shirt: SIMD3(Float(shirtColor.red), Float(shirtColor.green), Float(shirtColor.blue)))
    }

    static func dismantleNSView(_ view: VillagerPreviewNSView, coordinator: ()) { view.stop() }
}

@MainActor
final class VillagerPreviewNSView: NSView {
    private let metalLayer = CAMetalLayer()
    fileprivate var gpu: OfficeGPU?
    fileprivate var renderer: OfficeMetalRenderer?
    fileprivate var instance = AvatarInstance(id: "preview", clip: .idle)
    private var time = 0.0
    fileprivate var yaw: Float = -0.35
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer = metalLayer
        metalLayer.pixelFormat = OfficeGPU.colorFormat
        metalLayer.framebufferOnly = true
        Task { @MainActor in await setUp() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    fileprivate func setUp() async {
        guard let gpu = await OfficeGPU.shared(), let renderer = try? OfficeMetalRenderer(gpu: gpu) else { return }
        self.gpu = gpu
        self.renderer = renderer
        metalLayer.device = gpu.device
        // Küçük, yuvarlatılmış köşeli zemin ve üstünde halı.
        var mesh = OfficeMesh()
        mesh.appendBox(size: SIMD3(3, 0.06, 3), center: SIMD3(0, -0.03, 0), color: SIMD4(246, 236, 220, 0), layer: 0)
        mesh.appendBox(size: SIMD3(1.3, 0.012, 1.3), center: SIMD3(0, 0.006, 0), color: SIMD4(214, 226, 242, 0), layer: 0)
        renderer.setWorld(mesh, site: PlanRect(minX: -1.5, minZ: -1.5, maxX: 1.5, maxZ: 1.5))
        renderer.setLighting(OfficeDaylight.at(hour: 13))
        instance.position = .zero
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func update(look: AvatarLook, shirt: SIMD3<Float>) {
        instance.look = look
        instance.shirtColor = shirt
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
    }

    override func mouseDragged(with event: NSEvent) {
        yaw += Float(event.deltaX) * 0.012
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        guard let window, window.occlusionState.contains(.visible), bounds.width > 1,
              let gpu, let renderer, let drawable = metalLayer.nextDrawable(),
              let cb = gpu.queue.makeCommandBuffer() else { return }
        time += dt
        let clip = PreviewClips.clip(at: time)
        if instance.clip != clip { instance.play(clip, skeleton: gpu.skeleton) }
        instance.advance(dt: dt)
        instance.facing = yaw
        let size = (width: Double(bounds.width), height: Double(bounds.height))
        renderer.encode(to: drawable.texture, viewport: Self.viewport(size), viewSize: size, avatars: [instance], time: time, commandBuffer: cb)
        cb.present(drawable)
        cb.commit()
    }

    /// Köylüyü boydan, hafif üstten gösteren görünüm.
    static func viewport(_ size: OfficeViewport.ViewSize) -> OfficeViewport {
        let zoom = size.height / 2.1
        let fit = OfficeViewport(targetX: 0, targetZ: 0, zoom: zoom * 0.4, fitZoom: zoom * 0.4, planMinZ: -1.5)
        return CameraFollow.target(x: 0, z: 0, seated: false, zoom: zoom, fit: fit)
    }

    /// `--customizer-snapshot` için: önizlemenin bir anını ekran dışında çizer (aynı sahne ve görünüm).
    static func renderOffscreen(look: AvatarLook, shirt: SIMD3<Float>, size: (width: Int, height: Int), at time: Double) async -> CGImage? {
        let view = VillagerPreviewNSView()
        await view.setUp()
        view.stop()
        guard let gpu = view.gpu, let renderer = view.renderer else { return nil }
        view.update(look: look, shirt: shirt)
        let clip = PreviewClips.clip(at: time)
        view.instance.play(clip, skeleton: gpu.skeleton)
        view.instance.advance(dt: 1)
        view.instance.facing = view.yaw
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: OfficeGPU.colorFormat, width: size.width,
                                                                  height: size.height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = gpu.device.makeTexture(descriptor: descriptor), let cb = gpu.queue.makeCommandBuffer() else { return nil }
        let viewSize = (width: Double(size.width), height: Double(size.height))
        renderer.encode(to: texture, viewport: viewport(viewSize), viewSize: viewSize, avatars: [view.instance], time: time, commandBuffer: cb)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            cb.addCompletedHandler { _ in done.resume() }
            cb.commit()
        }
        var bytes = [UInt8](repeating: 0, count: size.width * size.height * 4)
        texture.getBytes(&bytes, bytesPerRow: size.width * 4, from: MTLRegionMake2D(0, 0, size.width, size.height), mipmapLevel: 0)
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: size.width, height: size.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size.width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
