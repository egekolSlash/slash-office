import AgentOfficeCore
import AppKit
import RealityKit
import SwiftUI

struct OfficeView: View {
    @Bindable var model: AppModel
    @State private var root = Entity()
    @State private var viewSize = CGSize(width: 800, height: 500)

    private var snapshot: OfficeSnapshot {
        let sessions = model.store.sessions
        let placements = OfficeLayout.place(sessions.map { (id: $0.id, project: $0.cwd) })
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let tiles = placements.compactMap { placement -> OfficeSnapshot.Tile? in
            guard let session = byID[placement.id] else { return nil }
            return .init(placement: placement, title: session.title, state: session.state, kind: model.kind(of: session.id))
        }
        return OfficeSnapshot(tiles: tiles, focused: model.layout.focused, grid: OfficeLayout.gridSize(placements),
                              aspect: Double(viewSize.width / max(viewSize.height, 1)))
    }

    var body: some View {
        let snapshot = snapshot
        RealityView { content in
            content.add(OfficeScene.light())
            content.add(root)
        } update: { _ in
            root.children.removeAll()
            root.addChild(OfficeScene.build(snapshot))
        }
        .realityViewCameraControls(.none)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        .overlay { OfficeLabels(snapshot: snapshot) }
        .overlay {
            // RealityView bir AppKit görünümü olarak SwiftUI katmanının üstünde durur ve fare olaylarını alır;
            // SwiftUI tıklaması ona hiç ulaşmaz. Üste konan küçük bir AppKit görünümü tıklamayı yakalar,
            // nokta aynı izometrik kamera tanımıyla karoya çevrilir.
            ClickCatcher { location, size, shift in
                let camera = OfficeScene.camera(for: snapshot.grid, aspect: Double(size.width / max(size.height, 1)))
                let id = camera.tile(atX: location.x, y: location.y, viewSize: (Double(size.width), Double(size.height)),
                                     tiles: snapshot.tiles.map(\.placement), tileSize: OfficeScene.tileSize,
                                     labelBox: OfficeLabels.labelBox(viewHeight: Double(size.height), camera: camera))
                DebugLog.write("office click \(location) in \(size) -> \(id ?? "nil")")
                guard let id else { return }
                if shift { model.addTerminal(id) } else { model.showTerminal(id) }
            }
        }
        .overlay {
            if snapshot.tiles.isEmpty {
                ContentUnavailableView("Ofis boş", systemImage: "building.2",
                                       description: Text("⌘N ile bir ajan başlat."))
            }
        }
    }
}

/// Tıklamaları SwiftUI yerine AppKit düzeyinde yakalar (sol üst orijinli nokta, görünüm boyutu, ⇧ basılı mı).
struct ClickCatcher: NSViewRepresentable {
    let onClick: (CGPoint, CGSize, Bool) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onClick = onClick
    }

    final class CatcherView: NSView {
        var onClick: ((CGPoint, CGSize, Bool) -> Void)?
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            frame.contains(point) ? self : nil
        }
        override func mouseUp(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onClick?(point, bounds.size, event.modifierFlags.contains(.shift))
        }
    }
}
