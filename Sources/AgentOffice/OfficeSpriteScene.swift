import AgentOfficeCore
import AppKit
import SpriteKit

/// Ofis sahnesi (spec §6). Dünya düğümü ekran düzleminde (1 birim = 1 karo) çizilir; kamera onu kaydırıp ölçekler.
/// Aşama 1: odalar, masalar ve karakterler geçici şekillerle.
@MainActor
final class OfficeSpriteScene: SKScene {
    let officeCamera = OfficeCamera()
    private let world = SKNode()
    private var roomNodes: [String: (room: OfficePlan.Room, node: SKNode)] = [:]
    private var deskNodes: [String: (desk: OfficePlan.Desk, room: OfficePlan.Room, info: OfficeDeskInfo, node: SKNode)] = [:]
    private var corridorNode: SKNode?
    private var corridorRect: PlanRect?

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.15, alpha: 1)
        addChild(world)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmıyor") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        officeCamera.viewSize = (Double(size.width), Double(size.height))
    }

    override func update(_ currentTime: TimeInterval) {
        officeCamera.step()
        applyCamera()
    }

    private func applyCamera() {
        let viewport = officeCamera.viewport
        world.setScale(viewport.zoom)
        world.position = CGPoint(x: Double(size.width) / 2 - viewport.centerX * viewport.zoom,
                                 y: Double(size.height) / 2 - viewport.centerY * viewport.zoom)
    }

    /// Planı çizer; sadece değişen oda ve masaları yeniden kurar.
    func render(plan: OfficePlan, desks: [String: OfficeDeskInfo]) {
        if corridorRect != plan.corridor {
            corridorNode?.removeFromParent()
            corridorRect = plan.corridor
            let node = Self.floor(plan.corridor, color: NSColor(white: 0.17, alpha: 1))
            node.zPosition = -1000
            world.addChild(node)
            corridorNode = node
        }
        let rooms = Dictionary(uniqueKeysWithValues: plan.rooms.map { ($0.key, $0) })
        for (key, entry) in roomNodes where rooms[key] != entry.room {
            entry.node.removeFromParent()
            roomNodes[key] = nil
        }
        for room in plan.rooms where roomNodes[room.key] == nil {
            let node = Self.roomNode(room)
            world.addChild(node)
            roomNodes[room.key] = (room, node)
        }
        let placed = Dictionary(uniqueKeysWithValues: plan.rooms.flatMap { room in room.desks.map { ($0.id, (desk: $0, room: room)) } })
        for (id, entry) in deskNodes where placed[id]?.desk != entry.desk || placed[id]?.room != entry.room || desks[id] != entry.info {
            entry.node.removeFromParent()
            deskNodes[id] = nil
        }
        for (id, place) in placed where deskNodes[id] == nil {
            guard let info = desks[id] else { continue }
            let node = Self.deskNode(place.desk, in: place.room, info: info)
            world.addChild(node)
            deskNodes[id] = (place.desk, place.room, info, node)
        }
        applyCamera()
    }

    // MARK: - Geçici şekiller (aşama 2'de sprite'larla değişir)

    static func point(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        let p = OfficeViewport.screenPlane(x: x, y: y, z: z)
        return CGPoint(x: p.x, y: p.y)
    }

    static func polygon(_ points: [CGPoint], fill: NSColor, stroke: NSColor? = nil) -> SKShapeNode {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        let node = SKShapeNode(path: path)
        node.fillColor = fill
        node.strokeColor = stroke ?? .clear
        node.lineWidth = stroke == nil ? 0 : 0.02
        node.isAntialiased = true
        return node
    }

    static func floor(_ rect: PlanRect, color: NSColor) -> SKShapeNode {
        polygon([point(rect.minX, 0, rect.minZ), point(rect.maxX, 0, rect.minZ),
                 point(rect.maxX, 0, rect.maxZ), point(rect.minX, 0, rect.maxZ)], fill: color)
    }

    /// Dikey duvar: (x1,z1)–(x2,z2) zemin çizgisinden `height` yüksekliğe.
    static func wall(from a: (Double, Double), to b: (Double, Double), height: Double, color: NSColor) -> SKShapeNode {
        polygon([point(a.0, 0, a.1), point(b.0, 0, b.1), point(b.0, height, b.1), point(a.0, height, a.1)], fill: color)
    }

    static func projectColor(_ key: String) -> NSColor {
        let c = ProjectPalette.colors[ProjectPalette.index(for: key)]
        return NSColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    static func roomNode(_ room: OfficePlan.Room) -> SKNode {
        let node = SKNode()
        let rect = room.rect
        let tint = projectColor(room.key)
        let floor = floor(rect, color: NSColor(red: 0.22, green: 0.23, blue: 0.32, alpha: 1).blended(withFraction: 0.12, of: tint) ?? .darkGray)
        floor.zPosition = CGFloat(OfficeDepth.floor(room))
        node.addChild(floor)
        let heights = room.backWallHeights
        let low = OfficePlan.lowWallHeight
        let back = NSColor(red: 0.30, green: 0.32, blue: 0.44, alpha: 1)
        let side = NSColor(red: 0.25, green: 0.27, blue: 0.38, alpha: 1)
        // Arka duvarlar: dış kenarda tam boy, içeride alçak; ön duvarlar hep alçak (spec §3, kesit görünüm).
        let backWalls = [
            wall(from: (rect.minX, rect.minZ), to: (rect.maxX, rect.minZ), height: heights.z, color: back),
            wall(from: (rect.minX, rect.minZ), to: (rect.minX, rect.maxZ), height: heights.x, color: side),
        ]
        let frontWalls = [
            wall(from: (rect.minX, rect.maxZ), to: (rect.maxX, rect.maxZ), height: low, color: side.withAlphaComponent(0.9)),
            wall(from: (rect.maxX, rect.minZ), to: (rect.maxX, rect.maxZ), height: low, color: back.withAlphaComponent(0.9)),
        ]
        for wall in backWalls { wall.zPosition = CGFloat(OfficeDepth.backWalls(room)); node.addChild(wall) }
        for wall in frontWalls { wall.zPosition = CGFloat(OfficeDepth.frontWalls(room)); node.addChild(wall) }
        // Kapı: koridora bakan (alçak) duvarda, proje renginde bir eşik.
        let door = wall(from: (room.doorX, room.doorZ - 0.35), to: (room.doorX, room.doorZ + 0.35), height: low + 0.02,
                        color: tint.withAlphaComponent(0.9))
        door.zPosition = CGFloat(room.side == .left ? OfficeDepth.frontWalls(room) : OfficeDepth.backWalls(room)) + 0.5
        node.addChild(door)
        return node
    }

    static func stateColor(_ state: AgentState) -> NSColor {
        switch state {
        case .working: NSColor(red: 0.25, green: 0.52, blue: 0.95, alpha: 1)
        case .waiting: NSColor(red: 0.98, green: 0.58, blue: 0.18, alpha: 1)
        case .idle, .starting: NSColor(white: 0.62, alpha: 1)
        case .exited: NSColor(white: 0.32, alpha: 1)
        }
    }

    static func deskNode(_ desk: OfficePlan.Desk, in room: OfficePlan.Room, info: OfficeDeskInfo) -> SKNode {
        let node = SKNode()
        node.zPosition = CGFloat(OfficeDepth.desk(desk, in: room))
        // Durum renginde zemin ışığı.
        let glow = floor(PlanRect(minX: desk.x - 0.45, minZ: desk.z - 0.45, maxX: desk.x + 0.45, maxZ: desk.z + 0.45),
                         color: stateColor(info.state).withAlphaComponent(info.focused ? 0.75 : 0.5))
        glow.zPosition = -1
        if case .waiting = info.state {
            // Bekleyen masa yanıp söner; ofisin tek sürekli animasyonu bu.
            glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.6), .fadeAlpha(to: 1, duration: 0.6)])))
        }
        node.addChild(glow)
        // Masa üstü (yükseklik 0.45) ve monitör (masanın arka kenarında).
        let top = polygon([point(desk.x - 0.35, 0.45, desk.z - 0.3), point(desk.x + 0.35, 0.45, desk.z - 0.3),
                           point(desk.x + 0.35, 0.45, desk.z + 0.05), point(desk.x - 0.35, 0.45, desk.z + 0.05)],
                          fill: NSColor(white: 0.85, alpha: 1))
        node.addChild(top)
        let screenColor: NSColor = switch info.state {
        case .working, .waiting: .systemTeal
        case .exited: .black
        default: NSColor(white: 0.25, alpha: 1)
        }
        let monitor = wall(from: (desk.x - 0.17, desk.z - 0.25), to: (desk.x + 0.17, desk.z - 0.25), height: 0.25, color: screenColor)
        monitor.position = CGPoint(x: 0, y: point(0, 0.45, 0).y)
        monitor.zPosition = 1
        node.addChild(monitor)
        // Karakter: Claude oturumunda (durmamışsa) ya da hook gönderen claude çalışan terminalde.
        let hasCharacter = info.state != .exited && (info.kind == .claude || info.state != .idle)
        if hasCharacter {
            let standing: Bool = if case .waiting = info.state { true } else { false }
            let base = standing ? point(desk.x + 0.35, 0, desk.z + 0.35) : point(desk.x, 0.3, desk.z + 0.3)
            let shirt = projectColor(info.roomKey)
            let body = SKShapeNode(rectOf: CGSize(width: 0.26, height: 0.34), cornerRadius: 0.12)
            body.fillColor = shirt
            body.strokeColor = .clear
            body.position = CGPoint(x: base.x, y: base.y + 0.17)
            let head = SKShapeNode(circleOfRadius: 0.13)
            head.fillColor = NSColor(red: 0.95, green: 0.78, blue: 0.62, alpha: 1)
            head.strokeColor = .clear
            head.position = CGPoint(x: base.x, y: base.y + 0.46)
            body.zPosition = 2
            head.zPosition = 3
            node.addChild(body)
            node.addChild(head)
        }
        return node
    }
}
