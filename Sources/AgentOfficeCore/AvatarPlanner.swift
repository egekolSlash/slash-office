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
    // v5 aşama 2: canlı köylüler (Blender zaman çizelgesi 171–638).
    case lookAround, sitSip, sitThink, sitStretch, stretch, waitTap, cheer, inspect, drink, sitDown, standUp, sofaSit

    public var frames: ClosedRange<Int> {
        switch self {
        case .idle: 1...24
        case .walk: 31...54
        case .sitType: 61...84
        case .sitDoze: 91...138
        case .wave: 141...164
        case .lookAround: 171...218
        case .sitSip: 221...268
        case .sitThink: 271...318
        case .sitStretch: 321...356
        case .stretch: 361...396
        case .waitTap: 401...424
        case .cheer: 431...454
        case .inspect: 461...508
        case .drink: 511...546
        case .sitDown: 551...562
        case .standUp: 571...582
        case .sofaSit: 591...638
        }
    }

    /// Döngü mü (bitince baştan), tek seferlik mi (bitince davranış devam eder).
    public var loops: Bool {
        switch self {
        case .idle, .walk, .sitType, .sitDoze, .wave, .lookAround, .sofaSit: true
        default: false
        }
    }

    /// Oturarak oynanır (taburede ya da koltukta).
    public var seated: Bool {
        switch self {
        case .sitType, .sitDoze, .sitSip, .sitThink, .sitStretch, .sofaSit: true
        default: false
        }
    }

    /// Süre (sn): klipler 24 fps, son kare ilkine denk.
    public var duration: Double { Double(frames.count - 1) / 24 }
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
    public static let seatOffset = 0.32
}

/// Odanın dinlenme köşesindeki ilgi noktası (v5 spec §4): eşya burada durur, köylüler (aşama 2) burada oyalanır.
public struct RoomSpot: Equatable, Sendable {
    public enum Kind: String, Sendable { case sofa, coffeeTable, waterCooler, plant }
    public var kind: Kind
    public var x: Double
    public var z: Double
    /// Eşyanın baktığı yön: y ekseni etrafında radyan, 0 = +z.
    public var facing: Double
}

extension OfficePlan.Room {
    public var doorInside: PlanPoint { PlanPoint(x: corridorEdgeX + outward * 0.35, z: doorZ) }
    public var doorOutside: PlanPoint { PlanPoint(x: corridorEdgeX - outward * 0.6, z: doorZ) }
    public func seat(for desk: OfficePlan.Desk) -> PlanPoint { PlanPoint(x: desk.x, z: desk.z - DeskGeometry.seatOffset) }
    /// Masanın koridor tarafındaki boşluk (iki masa sütunu arası ya da koridor duvarının dibi): köylüler masaya
    /// buradan yürür, beklerken burada durur.
    public func aisleX(for desk: OfficePlan.Desk) -> Double { desk.x - outward * OfficePlan.columnSpacing / 2 }
    public func standSpot(for desk: OfficePlan.Desk) -> PlanPoint { PlanPoint(x: aisleX(for: desk), z: desk.z + 0.1) }

    /// Dinlenme köşesi: dış duvar dibinde koltuk (içe bakar) ve önünde sehpa, dış ön köşede bitki, koridor
    /// tarafındaki ön köşede sebil.
    public var spots: [RoomSpot] {
        let outer = corridorEdgeX + outward * width
        let inward = outward > 0 ? -Double.pi / 2 : Double.pi / 2
        return [
            RoomSpot(kind: .sofa, x: outer - outward * 0.45, z: z + 4.95, facing: inward),
            RoomSpot(kind: .coffeeTable, x: outer - outward * 1.25, z: z + 4.95, facing: 0),
            RoomSpot(kind: .plant, x: outer - outward * 0.4, z: z + 5.8, facing: 0),
            RoomSpot(kind: .waterCooler, x: corridorEdgeX + outward * 0.4, z: z + 5.75, facing: -inward),
        ]
    }
}

public enum AvatarSpot: Equatable, Sendable { case outside, seat, stand }

/// Dik açılı yol (v5 spec §4): masa alanında masanın koridor tarafındaki boşlukta, önde yürüme şeridinde yürünür;
/// masaların içinden geçmez. Oda dışına sadece kapıdan çıkılır.
public enum AvatarRoute {
    public static let speed = 1.4

    static func point(_ spot: AvatarSpot, desk: OfficePlan.Desk, room: OfficePlan.Room) -> PlanPoint {
        switch spot {
        case .outside: room.doorOutside
        case .seat: room.seat(for: desk)
        case .stand: room.standSpot(for: desk)
        }
    }

    public static func route(from start: PlanPoint, to spot: AvatarSpot, desk: OfficePlan.Desk, room: OfficePlan.Room) -> [PlanPoint] {
        let aisle = room.aisleX(for: desk), walkway = room.doorZ
        var path = [start]
        func go(_ p: PlanPoint) { path.append(p) }
        // Kapının dışındaysa önce içeri gir.
        if start == room.doorOutside { go(room.doorInside) }
        var here = path.last!
        // Masanın boşluğuna geç: masa alanındaysa (ör. tabureden) yana, öndeyse önce yürüme şeridine.
        if abs(here.x - aisle) > 0.01 {
            if here.z < walkway - 0.01 {
                go(PlanPoint(x: aisle, z: here.z))
            } else {
                if abs(here.z - walkway) > 0.01 { go(PlanPoint(x: here.x, z: walkway)) }
                go(PlanPoint(x: aisle, z: walkway))
            }
        }
        here = path.last!
        switch spot {
        case .outside:
            go(PlanPoint(x: aisle, z: walkway))
            go(room.doorInside)
            go(room.doorOutside)
        case .seat:
            let seat = room.seat(for: desk)
            go(PlanPoint(x: aisle, z: seat.z))
            go(seat)
        case .stand:
            go(room.standSpot(for: desk))
        }
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
    /// Köylünün bulunduğu odanın o anki yeri; oda kayar ya da büyürse köylü ışınlanır (duvardan yürümesin).
    public var room: PlanRect?
    public init(point: PlanPoint, roomKey: String, room: PlanRect? = nil) {
        self.point = point; self.roomKey = roomKey; self.room = room
    }
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
        let roomMoved = current.room.map { $0 != room.rect } ?? false
        if current.roomKey != room.key || roomMoved || !room.rect.insetBy(-0.7).contains(x: current.point.x, z: current.point.z) {
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
