import AgentOfficeCore
import AppKit
import Metal
import QuartzCore
import SwiftUI

/// Ofisi kendi `CAMetalLayer`'ına çizen görünüm (spec v4 §3). Ana thread kare başına iş yapmaz: sadece durum
/// değişince (plan, masalar, görünüş, kamera, jest) çizim döngüsüne bildirir. Çizim, köylü simülasyonu ve kemik
/// matrisleri `OfficeRenderLoop`'un kendi thread'indedir. Kamera geçişi sürerken (sadece o sırada) ana thread'de
/// bir `displayLink` kamerayı adımlar. Jestler aşama 1'deki gibi.
final class OfficeMetalView: NSView {
    var interactive = false
    var mini = false { didSet { if mini != oldValue { postVisibility() } } }
    var onClick: ((_ x: Double, _ y: Double, _ clickCount: Int, _ shift: Bool) -> Void)?
    var onRightClick: ((_ x: Double, _ y: Double) -> Void)?
    var onPan: ((_ dx: Double, _ dy: Double) -> Void)?
    var onZoom: ((_ factor: Double, _ x: Double, _ y: Double) -> Void)?
    var onResetKey: (() -> Void)?

    private let metalLayer = CAMetalLayer()
    private let loop: OfficeRenderLoop
    private let camera: OfficeCamera
    private var occlusionObserver: NSObjectProtocol?
    private var cameraLink: CADisplayLink?
    private var lastScene: OfficeSceneInput?
    private var worldKey: OfficeWorldKey?
    private var worldGeneration = 0

    init(gpu: OfficeGPU, camera: OfficeCamera) throws {
        self.camera = camera
        metalLayer.device = gpu.device
        metalLayer.pixelFormat = OfficeGPU.colorFormat
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        metalLayer.maximumDrawableCount = 3
        metalLayer.displaySyncEnabled = true
        loop = try OfficeRenderLoop(gpu: gpu, layer: metalLayer)
        super.init(frame: .zero)
        wantsLayer = true
        layer = metalLayer
        observeCamera()
        loop.start()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmıyor") }

    isolated deinit {
        loop.stop()
        cameraLink?.invalidate()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }

    override func makeBackingLayer() -> CALayer { metalLayer }
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { interactive }

    // MARK: - Durum

    /// Sahne girdisi değiştiyse çizim döngüsüne gönderir; dünya mesh'i (plan, stil, masa türü değişince) arka planda kurulur.
    func update(_ scene: OfficeSceneInput) {
        guard scene != lastScene else { return }
        lastScene = scene
        loop.post(scene: scene)
        let key = OfficeWorldKey(plan: scene.plan, terminals: scene.terminals, styles: scene.styles)
        guard key != worldKey else { return }
        worldKey = key
        worldGeneration += 1
        let generation = worldGeneration
        let loop = loop
        let colors = scene.projectColors
        Task.detached(priority: .userInitiated) {
            let mesh = OfficeWorldBuilder.build(plan: key.plan, terminalDesks: key.terminals,
                                                style: { key.styles[$0] ?? RoomStyle.default(for: $0) },
                                                projectColor: { colors[$0] ?? (0.6, 0.6, 0.6) }, art: loop.gpu.art)
            loop.post(world: mesh, bounds: key.plan.bounds, generation: generation)
        }
    }

    /// Kamera değişince (jest, sığdırma, geçiş) yeni görünümü bildirir; geçiş varsa ekranla eş zamanlı adımlar.
    private func observeCamera() {
        withObservationTracking {
            _ = camera.viewport
            _ = camera.viewSize
            _ = camera.target
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.cameraChanged()
                self?.observeCamera()
            }
        }
        cameraChanged()
    }

    private func cameraChanged() {
        loop.post(viewport: camera.viewport, viewSize: camera.viewSize, cameraMoving: camera.target != nil)
        if camera.target != nil, cameraLink == nil, window != nil {
            let link = displayLink(target: self, selector: #selector(stepCamera))
            link.add(to: .main, forMode: .common)
            cameraLink = link
        }
    }

    @objc private func stepCamera() {
        camera.step()
        if camera.target == nil {
            cameraLink?.invalidate()
            cameraLink = nil
        }
    }

    // MARK: - Görünürlük ve boyut

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        loop.post(drawableSize: CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1)))
        postVisibility()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        if let window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.postVisibility() }
            }
            if interactive { window.makeFirstResponder(self) }
        } else {
            cameraLink?.invalidate()
            cameraLink = nil
        }
        postVisibility()
    }

    override func viewDidHide() {
        super.viewDidHide()
        postVisibility()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        postVisibility()
    }

    private func postVisibility() {
        let visible = window.map { !isHiddenOrHasHiddenAncestor && bounds.width > 1 && bounds.height > 1
            && $0.occlusionState.contains(.visible) } ?? false
        loop.post(visible: visible, mini: mini)
    }

    // MARK: - Jestler

    private func point(_ event: NSEvent) -> (Double, Double) {
        let p = convert(event.locationInWindow, from: nil)
        return (Double(p.x), Double(bounds.height - p.y))
    }

    override func mouseDown(with event: NSEvent) {
        if interactive { window?.makeFirstResponder(self) }
    }

    override func mouseUp(with event: NSEvent) {
        let (x, y) = point(event)
        onClick?(x, y, event.clickCount, event.modifierFlags.contains(.shift))
        loop.postInteraction()
    }

    override func rightMouseDown(with event: NSEvent) {
        let (x, y) = point(event)
        onRightClick?(x, y)
    }

    override func scrollWheel(with event: NSEvent) {
        guard interactive else { return super.scrollWheel(with: event) }
        let (x, y) = point(event)
        if event.modifierFlags.contains(.command) {
            let delta = Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.01 : 0.1)
            onZoom?(exp(delta), x, y)
        } else {
            let scale = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
            onPan?(Double(event.scrollingDeltaX) * scale, Double(event.scrollingDeltaY) * scale)
        }
        loop.postInteraction()
    }

    override func magnify(with event: NSEvent) {
        guard interactive else { return super.magnify(with: event) }
        let (x, y) = point(event)
        onZoom?(1 + Double(event.magnification), x, y)
        loop.postInteraction()
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        if interactive, event.charactersIgnoringModifiers == "0", flags.isEmpty {
            onResetKey?()
            loop.postInteraction()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// Çizim döngüsüne giden sahne: köylüler için masalar, görünüşler, renkler; dünya için plan, terminal masaları, stiller.
struct OfficeSceneInput: Equatable, Sendable {
    var plan: OfficePlan
    var desks: [String: AvatarDeskState]
    var looks: [String: AvatarLook]
    var styles: [String: RoomStyle]
    var terminals: Set<String>
    var projectColors: [String: AvatarLook.RGBA]

    static func == (a: Self, b: Self) -> Bool {
        a.plan == b.plan && a.desks == b.desks && a.looks == b.looks && a.styles == b.styles && a.terminals == b.terminals
            && a.projectColors.count == b.projectColors.count
            && a.projectColors.allSatisfy { key, c in b.projectColors[key].map { $0 == c } ?? false }
    }
}

private struct OfficeWorldKey: Equatable, Sendable {
    var plan: OfficePlan
    var terminals: Set<String>
    var styles: [String: RoomStyle]
}

/// Çizim thread'i (spec v4 §3): gelen durumu uygular, köylüleri ilerletir, kareyi çizer ve sunar.
/// Kare hızı `FramePacing`: native'de `nextDrawable` ekran yenilemesine kadar bekler; 12 fps'te kareler arası uyur;
/// duraklatılmışken yeni bir bildirim gelene kadar semaforda uyur (CPU harcamaz).
final class OfficeRenderLoop: @unchecked Sendable {
    let gpu: OfficeGPU
    private let layer: CAMetalLayer
    private let renderer: OfficeMetalRenderer
    private var sim: AvatarSim
    private let wake = DispatchSemaphore(value: 0)
    private let lock = NSLock()

    // Ana thread'den gelenler (kilitli).
    private struct Mailbox {
        var running = true
        var scene: OfficeSceneInput?
        var world: (mesh: OfficeMesh, bounds: PlanRect, generation: Int)?
        var viewport = OfficeViewport(centerX: 0, centerY: 0, zoom: 40)
        var viewSize: OfficeViewport.ViewSize = (800, 500)
        var cameraMoving = false
        var interactionUntil = 0.0
        var visible = false
        var mini = false
        var drawableSize: CGSize?
        var dirty = true
    }
    private var mailbox = Mailbox()

    // Sadece çizim thread'inde.
    private var synced = false
    private var worldGeneration = 0
    private var time = 0.0
    private var lastFrame = CACurrentMediaTime()
    private var lastMode = FramePacing.Mode.paused

    init(gpu: OfficeGPU, layer: CAMetalLayer) throws {
        self.gpu = gpu
        self.layer = layer
        renderer = try OfficeMetalRenderer(gpu: gpu)
        sim = AvatarSim(skeleton: gpu.skeleton)
    }

    func start() {
        let thread = Thread { [self] in run() }
        thread.name = "office-render"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        send { $0.running = false }
    }

    private func send(_ change: (inout Mailbox) -> Void) {
        lock.lock()
        change(&mailbox)
        mailbox.dirty = true
        lock.unlock()
        wake.signal()
    }

    func post(scene: OfficeSceneInput) { send { $0.scene = scene } }

    func post(world: OfficeMesh, bounds: PlanRect, generation: Int) {
        send { box in
            if generation >= (box.world?.generation ?? 0) { box.world = (world, bounds, generation) }
        }
    }

    func post(viewport: OfficeViewport, viewSize: OfficeViewport.ViewSize, cameraMoving: Bool) {
        send { $0.viewport = viewport; $0.viewSize = viewSize; $0.cameraMoving = cameraMoving }
    }

    func post(visible: Bool, mini: Bool) { send { $0.visible = visible; $0.mini = mini } }
    func post(drawableSize: CGSize) { send { $0.drawableSize = drawableSize } }
    /// Jest sonrası yarım saniye tam hız (kaydırma ve yakınlaştırma akıcı olsun).
    func postInteraction() { send { $0.interactionUntil = CACurrentMediaTime() + 0.5 } }

    // MARK: - Döngü

    private func run() {
        while true {
            lock.lock()
            let box = mailbox
            mailbox.scene = nil
            mailbox.world = nil
            mailbox.drawableSize = nil
            mailbox.dirty = false
            lock.unlock()
            guard box.running else { return }
            apply(box)

            let now = CACurrentMediaTime()
            let animating = !sim.instances.isEmpty
            let moving = sim.isMoving || sim.instances.contains { $0.blend < 1 }
            var mode = FramePacing.mode(moving: moving, interacting: box.cameraMoving || now < box.interactionUntil,
                                        animating: animating, visible: box.visible, mini: box.mini)
            // Duraklamadan önce son durumu bir kez çiz (ör. köylüsüz ofiste plan değişti, boş ofiste gökyüzü).
            let drawOnce = mode == .paused && box.dirty && box.visible
            if mode != lastMode {
                DebugLog.write("office frame mode \(lastMode) -> \(mode)")
                lastMode = mode
                lastFrame = now
            }
            if drawOnce { mode = .fixed(0) }
            switch mode {
            case .paused:
                wake.wait()
                lastFrame = CACurrentMediaTime()
            case .native:
                autoreleasepool { frame() }
            case .fixed(let fps):
                let start = CACurrentMediaTime()
                autoreleasepool { frame() }
                guard fps > 0 else { continue }
                let next = start + 1 / fps
                let wait = next - CACurrentMediaTime()
                // Bildirim gelirse erken uyanır (jest, yeni durum).
                if wait > 0 { _ = wake.wait(timeout: .now() + wait) }
            }
        }
    }

    private func apply(_ box: Mailbox) {
        if let size = box.drawableSize, layer.drawableSize != size { layer.drawableSize = size }
        if let world = box.world, world.generation > worldGeneration {
            worldGeneration = world.generation
            renderer.setWorld(world.mesh, plan: world.bounds)
        }
        if let scene = box.scene {
            sim.sync(plan: scene.plan, desks: scene.desks, looks: scene.looks, projectColors: scene.projectColors, live: synced)
            synced = true
        }
        viewport = box.viewport
        viewSize = box.viewSize
    }

    private var viewport = OfficeViewport(centerX: 0, centerY: 0, zoom: 40)
    private var viewSize: OfficeViewport.ViewSize = (800, 500)

    private func frame() {
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastFrame, 0), 0.1)
        lastFrame = now
        time += dt
        sim.tick(dt: dt)
        guard let drawable = layer.nextDrawable(), let cb = gpu.queue.makeCommandBuffer() else { return }
        renderer.encode(to: drawable.texture, viewport: viewport, viewSize: viewSize, avatars: sim.instances,
                        time: time, commandBuffer: cb)
        cb.present(drawable)
        cb.commit()
        OfficeMeasureWindow.frames.add(1, ordering: .relaxed)
    }
}

struct OfficeMetalRepresentable: NSViewRepresentable {
    let gpu: OfficeGPU
    let camera: OfficeCamera
    let scene: OfficeSceneInput
    var interactive: Bool
    let onClick: (Double, Double, Int, Bool) -> Void
    var onRightClick: (Double, Double) -> Void = { _, _ in }
    var onPan: (Double, Double) -> Void = { _, _ in }
    var onZoom: (Double, Double, Double) -> Void = { _, _, _ in }
    var onResetKey: () -> Void = {}

    func makeNSView(context: Context) -> NSView {
        guard let view = try? OfficeMetalView(gpu: gpu, camera: camera) else {
            DebugLog.write("office metal view failed")
            return NSView()
        }
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? OfficeMetalView else { return }
        view.interactive = interactive
        view.mini = !interactive
        view.onClick = onClick
        view.onRightClick = onRightClick
        view.onPan = onPan
        view.onZoom = onZoom
        view.onResetKey = onResetKey
        view.update(scene)
    }
}
