import AppKit
import SpriteKit
import SwiftUI

/// Ofis sahnesini gösteren SKView. Tıklamaları sol üst orijinli noktaya çevirir; pencere görünmezken sahneyi durdurur.
final class OfficeSKView: SKView {
    var onClick: ((_ x: Double, _ y: Double, _ clickCount: Int, _ shift: Bool) -> Void)?

    var interactive = false
    var onPan: ((_ dx: Double, _ dy: Double) -> Void)?
    var onZoom: ((_ factor: Double, _ x: Double, _ y: Double) -> Void)?
    var onResetKey: (() -> Void)?

    override var acceptsFirstResponder: Bool { interactive }

    override func mouseDown(with event: NSEvent) {
        if interactive { window?.makeFirstResponder(self) }
        super.mouseDown(with: event)
    }

    /// İki parmak kaydırma gezdirir; ⌘ + tekerlek yakınlaştırır.
    override func scrollWheel(with event: NSEvent) {
        guard interactive else { return super.scrollWheel(with: event) }
        let point = convert(event.locationInWindow, from: nil)
        let y = Double(bounds.height - point.y)
        if event.modifierFlags.contains(.command) {
            let delta = Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.01 : 0.1)
            onZoom?(exp(delta), Double(point.x), y)
        } else {
            let scale = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
            onPan?(Double(event.scrollingDeltaX) * scale, Double(event.scrollingDeltaY) * scale)
        }
    }

    override func magnify(with event: NSEvent) {
        guard interactive else { return super.magnify(with: event) }
        let point = convert(event.locationInWindow, from: nil)
        onZoom?(1 + Double(event.magnification), Double(point.x), Double(bounds.height - point.y))
    }

    override func keyDown(with event: NSEvent) {
        if interactive, event.charactersIgnoringModifiers == "0", event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            onResetKey?()
        } else {
            super.keyDown(with: event)
        }
    }
    private var occlusionObserver: NSObjectProtocol?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onClick?(Double(point.x), Double(bounds.height - point.y), event.clickCount, event.modifierFlags.contains(.shift))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        guard let window else { return }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePaused() }
        }
        updatePaused()
    }

    /// Pencere ekranda değilse kare çizilmez (spec §6, performans).
    func updatePaused() {
        isPaused = !(window?.occlusionState.contains(.visible) ?? false)
    }
}

struct OfficeSpriteView: NSViewRepresentable {
    let scene: OfficeSpriteScene
    var interactive: Bool
    let onClick: (_ x: Double, _ y: Double, _ clickCount: Int, _ shift: Bool) -> Void
    var onPan: (Double, Double) -> Void = { _, _ in }
    var onZoom: (Double, Double, Double) -> Void = { _, _, _ in }
    var onResetKey: () -> Void = {}

    func makeNSView(context: Context) -> OfficeSKView {
        let view = OfficeSKView()
        view.preferredFramesPerSecond = 30
        view.ignoresSiblingOrder = true
        view.allowsTransparency = false
        view.presentScene(scene)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: OfficeSKView, context: Context) {
        view.interactive = interactive
        view.onClick = onClick
        view.onPan = onPan
        view.onZoom = onZoom
        view.onResetKey = onResetKey
        if view.scene !== scene { view.presentScene(scene) }
    }
}
