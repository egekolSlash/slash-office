import Foundation

/// Köylünün ne yaptığı (spec §5).
public enum AvatarActivity: Equatable, Sendable {
    case typing, dozing, waving, away

    public static func `for`(state: AgentState) -> AvatarActivity {
        switch state {
        case .working: .typing
        case .waiting: .waving
        case .idle, .starting: .dozing
        case .exited: .away
        }
    }

    /// Aşama 1 kuralı: Claude oturumunda her zaman; terminalde sadece bir şey çalışırken (hook'lu claude dahil).
    public static func hasAvatar(kind: SessionKind, state: AgentState) -> Bool {
        kind == .claude || (state != .idle && state != .starting && state != .exited)
    }
}

/// Animasyon klipleri ve Blender zaman çizelgesindeki kareleri (24 fps).
public enum AvatarClip: String, CaseIterable, Sendable {
    case idle, walk, sitType, sitDoze, wave

    public var frames: ClosedRange<Int> {
        switch self {
        case .idle: 1...24
        case .walk: 31...54
        case .sitType: 61...84
        case .sitDoze: 91...138
        case .wave: 141...164
        }
    }
}

public struct PlanPoint: Equatable, Sendable {
    public var x: Double, z: Double
    public init(x: Double, z: Double) { self.x = x; self.z = z }
    func distance(to other: PlanPoint) -> Double { hypot(x - other.x, z - other.z) }
}

/// Masa takımının ölçüleri (karo): köylü masanın arkasında (küçük z) oturur, +z'ye bakar.
public enum DeskGeometry {
    public static let deskHalfWidth = 0.35
    public static let deskHalfDepth = 0.22
    public static let seatOffset = 0.42
}

extension OfficePlan.Room {
    /// Masa sütunları arasındaki yürüme şeridi.
    public var laneX: Double { x + Double(width) / 2 }
    public var doorInside: PlanPoint { PlanPoint(x: side == .left ? doorX - 0.3 : doorX + 0.3, z: doorZ) }
    public var doorOutside: PlanPoint { PlanPoint(x: side == .left ? doorX + 0.6 : doorX - 0.6, z: doorZ) }
    public func seat(for desk: OfficePlan.Desk) -> PlanPoint { PlanPoint(x: desk.x, z: desk.z - DeskGeometry.seatOffset) }
    /// Beklerken masanın yanında, şeritte durur.
    public func standSpot(for desk: OfficePlan.Desk) -> PlanPoint { PlanPoint(x: laneX, z: desk.z + 0.1) }
}

public enum AvatarSpot: Equatable, Sendable { case outside, seat, stand }

/// Dik açılı yol: bulunulan nokta → şerit → hedefin hizası → hedef (masaların içinden geçmez).
public enum AvatarRoute {
    public static let speed = 1.4

    static func point(_ spot: AvatarSpot, desk: OfficePlan.Desk, room: OfficePlan.Room) -> PlanPoint {
        switch spot {
        case .outside: room.doorOutside
        case .seat: room.seat(for: desk)
        case .stand: room.standSpot(for: desk)
        }
    }

    /// Şeritten hedefe giden ara noktalar (şerit tarafından başlayarak).
    static func approach(_ spot: AvatarSpot, desk: OfficePlan.Desk, room: OfficePlan.Room) -> [PlanPoint] {
        switch spot {
        case .outside: [PlanPoint(x: room.laneX, z: room.doorZ), room.doorInside, room.doorOutside]
        case .seat: [PlanPoint(x: room.laneX, z: room.seat(for: desk).z), room.seat(for: desk)]
        case .stand: [room.standSpot(for: desk)]
        }
    }

    public static func route(from start: PlanPoint, to spot: AvatarSpot, desk: OfficePlan.Desk, room: OfficePlan.Room) -> [PlanPoint] {
        var path = [start]
        // Kapının dışındaysa önce içeri gir; masa hizasındaysa önce şeride çık.
        if start == room.doorOutside {
            path += [room.doorInside, PlanPoint(x: room.laneX, z: room.doorZ)]
        } else if abs(start.x - room.laneX) > 0.01 {
            path.append(PlanPoint(x: room.laneX, z: start.z))
        }
        let approach = approach(spot, desk: desk, room: room)
        if let first = approach.first, let last = path.last, abs(last.z - first.z) > 0.01 {
            path.append(PlanPoint(x: room.laneX, z: first.z))
        }
        path += approach
        // Ardışık aynı noktaları at.
        return path.reduce(into: []) { result, p in
            if let last = result.last, last.distance(to: p) < 0.01 { return }
            result.append(p)
        }
    }
}

public struct AvatarPose: Equatable, Sendable {
    public var point: PlanPoint
    public var roomKey: String
    public init(point: PlanPoint, roomKey: String) { self.point = point; self.roomKey = roomKey }
}

public enum AvatarStep: Equatable, Sendable {
    case place(PlanPoint, AvatarClip, facing: Double)
    case walk([PlanPoint], then: AvatarClip, facing: Double, hideAtEnd: Bool)
    case hide
}

/// Planlayıcı: köylünün bulunduğu yer ve ajanın durumu → yerleştir, yürü ya da gizle.
/// `facing`: y ekseni etrafında radyan; 0 = +z (kameraya doğru).
public enum AvatarPlanner {
    public static func plan(current: AvatarPose?, activity: AvatarActivity, desk: OfficePlan.Desk,
                            room: OfficePlan.Room, live: Bool) -> AvatarStep {
        let (spot, clip): (AvatarSpot, AvatarClip) = switch activity {
        case .typing: (.seat, .sitType)
        case .dozing: (.seat, .sitDoze)
        case .waving: (.stand, .wave)
        case .away: (.outside, .idle)
        }
        let target = AvatarRoute.point(spot, desk: desk, room: room)
        guard live else { return activity == .away ? .hide : .place(target, clip, facing: 0) }
        // İlk kez beliren köylü kapıdan girer.
        guard let current else {
            if activity == .away { return .hide }
            return .walk(AvatarRoute.route(from: room.doorOutside, to: spot, desk: desk, room: room), then: clip, facing: 0, hideAtEnd: false)
        }
        // Oda değişti ya da masa çok uzaklaştı: ışınla (odalar arası yürüme yok).
        if current.roomKey != room.key || !room.rect.insetBy(-0.7).contains(x: current.point.x, z: current.point.z) {
            return activity == .away ? .hide : .place(target, clip, facing: 0)
        }
        if current.point.distance(to: target) < 0.05 { return .place(target, clip, facing: 0) }
        return .walk(AvatarRoute.route(from: current.point, to: spot, desk: desk, room: room),
                     then: clip, facing: 0, hideAtEnd: activity == .away)
    }
}

extension PlanRect {
    /// Negatif değer dikdörtgeni büyütür.
    func insetBy(_ amount: Double) -> PlanRect {
        PlanRect(minX: minX + amount, minZ: minZ + amount, maxX: maxX - amount, maxZ: maxZ - amount)
    }
}
