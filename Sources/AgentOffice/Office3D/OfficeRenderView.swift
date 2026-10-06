import AgentOfficeCore
import AppKit
import Metal
import QuartzCore
import SwiftUI

/// 3D ofisi kendi `CAMetalLayer`'ına çizen görünüm (spec §6). `RealityView` kare hızını sınırlayamadığı için
/// kare zamanlayıcısı burada: hareket varken 30, sakinken 12, görünmezken 0 fps (`FramePacing`).
/// Jestler aşama 1'deki gibi: iki parmak kaydırma, pinch ve ⌘ + tekerlek yakınlaştırma, `0` sığdırma.
final class OfficeRenderView: NSView {
    var scene: Office3DScene? { didSet { schedule() } }
    var interactive = false
    var mini = false
    var onClick: ((_ x: Double, _ y: Double, _ clickCount: Int, _ shift: Bool) -> Void)?
    var onRightClick: ((_ x: Double, _ y: Double) -> Void)?
    var onPan: ((_ dx: Double, _ dy: Double) -> Void)?
    var onZoom: ((_ factor: Double, _ x: Double, _ y: Double) -> Void)?
    var onResetKey: (() -> Void)?

    private let metalLayer = CAMetalLayer()
    private var timer: Timer?
    private var currentFPS: Double = 0
    private var lastFrame = CACurrentMediaTime()
    private var frameInFlight = false
    private var occlusionObserver: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm_srgb
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        layer = metalLayer
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmıyor") }

    override func makeBackingLayer() -> CALayer { metalLayer }
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { interactive }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
        scene?.camera.viewSize = (Double(bounds.width), Double(bounds.height))
        schedule()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        if let window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            }
            if interactive { window.makeFirstResponder(self) }
        }
        schedule()
    }

    override func removeFromSuperview() {
        timer?.invalidate()
        timer = nil
        super.removeFromSuperview()
    }

    // MARK: - Kare zamanlayıcısı

    private var visible: Bool {
        guard let window, !isHiddenOrHasHiddenAncestor, bounds.width > 1, bounds.height > 1 else { return false }
        return window.occlusionState.contains(.visible)
    }

    /// Hedef kare hızını hesaplar; değiştiyse zamanlayıcıyı yeniden kurar.
    func schedule() {
        let fps = scene == nil ? 0 : FramePacing.fps(moving: scene?.wantsFastFrames ?? false, interacting: false,
                                                     visible: visible, mini: mini)
        guard fps != currentFPS else { return }
        DebugLog.write("office fps \(currentFPS) -> \(fps) (visible: \(visible), mini: \(mini))")
        currentFPS = fps
        timer?.invalidate()
        timer = nil
        guard fps > 0 else { return }
        lastFrame = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1 / fps, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        frame()
    }

    private func frame() {
        guard let scene, !frameInFlight, let drawable = metalLayer.nextDrawable() else { return }
        let now = CACurrentMediaTime()
        let dt = min(now - lastFrame, 0.1)
        lastFrame = now
        frameInFlight = true
        do {
            try scene.renderFrame(to: drawable.texture, dt: dt) { [weak self] in
                drawable.present()
                DispatchQueue.main.async { self?.frameInFlight = false }
            }
        } catch {
            frameInFlight = false
            DebugLog.write("office render failed: \(error)")
        }
        schedule()
    }

    // MARK: - Jestler

    private func point(_ event: NSEvent) -> (Double, Double) {
        let p = convert(event.locationInWindow, from: nil)
        return (Double(p.x), Double(bounds.height - p.y))
    }

    private func interacted() {
        scene?.lastInteraction = Date()
        schedule()
    }

    override func mouseDown(with event: NSEvent) {
        if interactive { window?.makeFirstResponder(self) }
    }

    override func mouseUp(with event: NSEvent) {
        let (x, y) = point(event)
        onClick?(x, y, event.clickCount, event.modifierFlags.contains(.shift))
        interacted()
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
        interacted()
    }

    override func magnify(with event: NSEvent) {
        guard interactive else { return super.magnify(with: event) }
        let (x, y) = point(event)
        onZoom?(1 + Double(event.magnification), x, y)
        interacted()
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        if interactive, event.charactersIgnoringModifiers == "0", flags.isEmpty {
            onResetKey?()
            interacted()
        } else {
            super.keyDown(with: event)
        }
    }
}

struct OfficeRenderRepresentable: NSViewRepresentable {
    let scene: Office3DScene
    var interactive: Bool
    let onClick: (Double, Double, Int, Bool) -> Void
    var onRightClick: (Double, Double) -> Void = { _, _ in }
    var onPan: (Double, Double) -> Void = { _, _ in }
    var onZoom: (Double, Double, Double) -> Void = { _, _, _ in }
    var onResetKey: () -> Void = {}

    func makeNSView(context: Context) -> OfficeRenderView {
        let view = OfficeRenderView(frame: .zero)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: OfficeRenderView, context: Context) {
        view.interactive = interactive
        view.mini = !interactive
        view.onClick = onClick
        view.onRightClick = onRightClick
        view.onPan = onPan
        view.onZoom = onZoom
        view.onResetKey = onResetKey
        if view.scene !== scene { view.scene = scene }
        view.schedule()
    }
}
