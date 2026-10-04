import AgentOfficeCore
import AppKit
import RealityKit
import SwiftUI

struct OfficeView: View {
    @Bindable var model: AppModel
    @State private var root = Entity()

    private var snapshot: OfficeSnapshot {
        let sessions = model.store.sessions
        let placements = OfficeLayout.place(sessions.map { (id: $0.id, project: $0.cwd) })
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let tiles = placements.compactMap { placement -> OfficeSnapshot.Tile? in
            guard let session = byID[placement.id] else { return nil }
            return .init(placement: placement, title: session.title, state: session.state)
        }
        return OfficeSnapshot(tiles: tiles, focused: model.layout.focused, grid: OfficeLayout.gridSize(placements))
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
        .overlay { OfficeLabels(snapshot: snapshot) }
        .overlay {
            // RealityKit'in entity seçimi bu kurulumda tıklamaları almadı; tıklama noktası aynı izometrik
            // kamera tanımıyla karoya çevrilir.
            GeometryReader { geometry in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        let size = (width: Double(geometry.size.width), height: Double(geometry.size.height))
                        let camera = OfficeScene.camera(for: snapshot.grid)
                        guard let id = camera.tile(atX: location.x, y: location.y, viewSize: size,
                                                   tiles: snapshot.tiles.map(\.placement), tileSize: OfficeScene.tileSize)
                        else { return }
                        if NSEvent.modifierFlags.contains(.shift) { model.addTerminal(id) } else { model.showTerminal(id) }
                    }
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
