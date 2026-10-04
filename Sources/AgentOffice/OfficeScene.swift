import AgentOfficeCore
import AppKit
import RealityKit

/// Sahnenin çizilmesi için gereken her şey; değişmediyse sahne yeniden kurulmaz.
struct OfficeSnapshot: Equatable {
    struct Tile: Equatable {
        var placement: TilePlacement
        var title: String
        var state: AgentState
    }
    var tiles: [Tile]
    var focused: String?
    var grid: (columns: Int, rows: Int)

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tiles == rhs.tiles && lhs.focused == rhs.focused && lhs.grid == rhs.grid
    }
}

@MainActor
enum OfficeScene {
    static let tileSize: Float = 1.2
    static let tilePrefix = "tile-"

    static func build(_ snapshot: OfficeSnapshot) -> Entity {
        let root = Entity()
        for tile in snapshot.tiles {
            root.addChild(makeTile(tile, focused: snapshot.focused == tile.placement.id))
        }
        root.addChild(makeCamera(grid: snapshot.grid))
        return root
    }

    /// Tıklanan entity'den (ya da üstlerinden) oturum kimliğini bulur.
    static func sessionID(of entity: Entity) -> String? {
        var current: Entity? = entity
        while let node = current {
            if node.name.hasPrefix(tilePrefix) { return String(node.name.dropFirst(tilePrefix.count)) }
            current = node.parent
        }
        return nil
    }

    static func light() -> Entity {
        let light = DirectionalLight()
        light.light.intensity = 3000
        light.look(at: .zero, from: [2, 6, 4], relativeTo: nil)
        return light
    }

    // MARK: - Parçalar

    private static func makeTile(_ tile: OfficeSnapshot.Tile, focused: Bool) -> Entity {
        let size = tileSize
        let entity = Entity()
        entity.name = tilePrefix + tile.placement.id
        entity.position = tileOrigin(tile.placement)
        entity.components.set(InputTargetComponent())
        entity.components.set(CollisionComponent(shapes: [.generateBox(width: size, height: 1.2, depth: size)]))

        let exited = tile.state == .exited
        let waiting: Bool = if case .waiting = tile.state { true } else { false }

        // Kenar: bekleyen için turuncu, odaktaki için beyaz.
        if waiting || focused {
            entity.addChild(box(width: size * 0.99, height: 0.02, depth: size * 0.99, y: 0.0,
                                color: waiting ? .systemOrange : .white, unlit: true))
        }
        entity.addChild(box(width: size * 0.92, height: 0.04, depth: size * 0.92, y: 0.02,
                            color: exited ? .systemGray : projectColor(tile.placement.project)))
        // Masa, sandalye, monitör.
        entity.addChild(box(width: 0.7, height: 0.05, depth: 0.38, y: 0.42, z: -0.18, color: .init(white: 0.85, alpha: 1)))
        entity.addChild(box(width: 0.08, height: 0.4, depth: 0.08, y: 0.22, x: -0.3, z: -0.18, color: .init(white: 0.6, alpha: 1)))
        entity.addChild(box(width: 0.08, height: 0.4, depth: 0.08, y: 0.22, x: 0.3, z: -0.18, color: .init(white: 0.6, alpha: 1)))
        entity.addChild(box(width: 0.3, height: 0.05, depth: 0.3, y: 0.25, z: 0.2, color: .init(white: 0.3, alpha: 1)))
        entity.addChild(box(width: 0.34, height: 0.22, depth: 0.03, y: 0.58, z: -0.3,
                            color: monitorColor(tile.state), unlit: true))

        if !exited { entity.addChild(makeNPC(state: tile.state)) }
        // Etiketler ve `?` balonu SwiftUI ile sahnenin üstüne çizilir (OfficeView); 3D metin geometrinin arkasında kalıyordu.
        return entity
    }

    /// Kapsül NPC: çalışırken masada oturur, beklerken ayağa kalkar, boştayken geriye yaslanır.
    private static func makeNPC(state: AgentState) -> Entity {
        let npc = Entity()
        let skin = SimpleMaterial(color: .init(red: 0.85, green: 0.47, blue: 0.34, alpha: 1), isMetallic: false)
        let body = ModelEntity(mesh: .generateCylinder(height: 0.32, radius: 0.1), materials: [skin])
        let head = ModelEntity(mesh: .generateSphere(radius: 0.09), materials: [skin])
        head.position = [0, 0.26, 0]
        npc.addChild(body)
        npc.addChild(head)
        switch state {
        case .waiting:
            npc.position = [0.38, 0.22, 0.25]
        case .idle:
            npc.position = [0, 0.44, 0.22]
            npc.orientation = simd_quatf(angle: -0.35, axis: [1, 0, 0])
        default:
            npc.position = [0, 0.44, 0.18]
        }
        return npc
    }

    static func camera(for grid: (columns: Int, rows: Int)) -> IsoCamera {
        IsoCamera.fitting(columns: grid.columns, rows: grid.rows, tileSize: tileSize)
    }

    /// Bir karonun dünya konumu; etiketler bu noktadan yukarı doğru yerleştirilir.
    static func tileOrigin(_ placement: TilePlacement) -> SIMD3<Float> {
        [Float(placement.column) * tileSize, 0, Float(placement.row) * tileSize]
    }

    private static func makeCamera(grid: (columns: Int, rows: Int)) -> Entity {
        let iso = camera(for: grid)
        var ortho = OrthographicCameraComponent()
        ortho.scale = iso.scale
        let camera = Entity()
        camera.components.set(ortho)
        camera.look(at: iso.center, from: iso.eye, relativeTo: nil)
        return camera
    }

    private static func box(width: Float, height: Float, depth: Float, y: Float, x: Float = 0, z: Float = 0,
                            color: NSColor, unlit: Bool = false) -> ModelEntity {
        let material: any Material = unlit ? UnlitMaterial(color: color) : SimpleMaterial(color: color, isMetallic: false)
        let entity = ModelEntity(mesh: .generateBox(width: width, height: height, depth: depth), materials: [material])
        entity.position = [x, y, z]
        return entity
    }

    private static func projectColor(_ project: String) -> NSColor {
        let c = ProjectPalette.colors[ProjectPalette.index(for: project)]
        return NSColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    private static func monitorColor(_ state: AgentState) -> NSColor {
        switch state {
        case .working, .waiting: .systemTeal
        case .idle, .starting: .init(white: 0.25, alpha: 1)
        case .exited: .black
        }
    }
}
