import AppKit
import SpriteKit
import SwiftUI

/// Ofis sahnesini gösteren SKView. Tıklamaları sol üst orijinli noktaya çevirir; pencere görünmezken sahneyi durdurur.
final class OfficeSKView: SKView {
    var onClick: ((_ x: Double, _ y: Double, _ clickCount: Int, _ shift: Bool) -> Void)?
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
    let onClick: (_ x: Double, _ y: Double, _ clickCount: Int, _ shift: Bool) -> Void

    func makeNSView(context: Context) -> OfficeSKView {
        let view = OfficeSKView()
        view.preferredFramesPerSecond = 30
        view.ignoresSiblingOrder = true
        view.allowsTransparency = false
        view.presentScene(scene)
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: OfficeSKView, context: Context) {
        view.onClick = onClick
        if view.scene !== scene { view.presentScene(scene) }
    }
}
