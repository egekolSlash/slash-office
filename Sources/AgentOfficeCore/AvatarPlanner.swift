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
    // Ofis hayatı: masa başı (oturarak) ve eşya klipleri (Blender 641–1062).
    case sitDraw, sitWrite, sitRead, readBook, playArcade, drawBoard, stepBackLook, brewCoffee

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
        case .sitDraw: 641...688
        case .sitWrite: 691...738
        case .sitRead: 741...788
        case .readBook: 791...862
        case .playArcade: 865...912
        case .drawBoard: 915...962
        case .stepBackLook: 965...1012
        case .brewCoffee: 1015...1062
        }
    }

    /// Döngü mü (bitince baştan), tek seferlik mi (bitince davranış devam eder).
    public var loops: Bool {
        switch self {
        case .idle, .walk, .sitType, .sitDoze, .wave, .lookAround, .sofaSit, .readBook, .playArcade, .drawBoard: true
        default: false
        }
    }

    /// Oturarak oynanır (taburede ya da koltukta).
    public var seated: Bool {
        switch self {
        case .sitType, .sitDoze, .sitSip, .sitThink, .sitStretch, .sofaSit, .sitDraw, .sitWrite, .sitRead: true
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

/// Masa takımının ölçüleri (ofis hayatı): masa koridora döner; uzun kenarı z boyunca. Köylü masanın koridordan
/// uzak tarafındaki taburede oturur ve koridora bakar.
public enum DeskGeometry {
    /// x boyunca (koridora dik) yarı genişlik ve z boyunca yarı derinlik.
    public static let deskHalfWidth = 0.275
    public static let deskHalfDepth = 0.475
    /// Masa merkezinden taburenin uzaklığı (dışa doğru).
    public static let seatOffset = 0.40
}

/// Odadaki ilgi noktası (v5 spec §4, ofis hayatı §B2): eşya burada durur, köylüler burada oyalanır.
public struct RoomSpot: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case sofa, coffeeTable, waterCooler, plant, bookshelf, arcade, whiteboard, coffeeMachine

        var furniture: RoomFurniture { RoomFurniture(rawValue: rawValue)! }
    }
    public var kind: Kind
    public var x: Double
    public var z: Double
    /// Eşyanın baktığı yön: y ekseni etrafında radyan, 0 = +z.
    public var facing: Double

    /// Eşyanın tabanı: bakış yönü boyunca ve ona dik yarı uzunluklar; dairesel olanlarda yarıçap.
    var footprint: (along: Double, across: Double, round: Bool) {
        switch kind {
        case .sofa: (0.275, 0.575, false)
        case .coffeeTable: (0.28, 0.28, true)
        case .waterCooler: (0.16, 0.16, false)
        case .plant: (0.15, 0.15, true)
        case .bookshelf: (0.16, 0.46, false)
        case .arcade: (0.3, 0.29, false)
        case .whiteboard: (0.12, 0.62, false)
        case .coffeeMachine: (0.235, 0.29, false)
        }
    }
}

extension OfficePlan.Room {
    public var doorInside: PlanPoint { PlanPoint(x: corridorEdgeX + outward * 0.35, z: doorZ) }
    public var doorOutside: PlanPoint { PlanPoint(x: corridorEdgeX - outward * 0.6, z: doorZ) }
    /// Tabure: yatayda masanın arkasında (küçük z), dikeyde masanın koridordan uzak tarafında.
    public func seat(for desk: OfficePlan.Desk) -> PlanPoint {
        switch deskOrientation {
        case .horizontal: PlanPoint(x: desk.x, z: desk.z - DeskGeometry.seatOffset)
        case .vertical: PlanPoint(x: desk.x + outward * DeskGeometry.seatOffset, z: desk.z)
        }
    }
    /// Kameraya (+z, ekranın altına) dönük yön: masanın yanında ayakta bekleyen köylü böyle durur.
    public static let cameraFacing = 0.0
    /// Masada oturan köylünün yönü: yatayda kameraya, dikeyde koridora (sol oda +x, sağ oda −x). Masa da bu açıyla döner.
    public func seatFacing(for desk: OfficePlan.Desk) -> Double {
        switch deskOrientation {
        case .horizontal: Self.cameraFacing
        case .vertical: -outward * Double.pi / 2
        }
    }
    /// Masanın x ve z boyunca yarı ölçüleri (yöne göre; uzun kenar yatayda x, dikeyde z boyunca).
    public var deskHalfExtents: (x: Double, z: Double) {
        switch deskOrientation {
        case .horizontal: (DeskGeometry.deskHalfDepth, DeskGeometry.deskHalfWidth)
        case .vertical: (DeskGeometry.deskHalfWidth, DeskGeometry.deskHalfDepth)
        }
    }
    /// Taburenin arkasındaki boşluk (bir sonraki masa sütununa kadar): köylüler masaya buradan yürür.
    public func aisleX(for desk: OfficePlan.Desk) -> Double { desk.x + outward * OfficePlan.columnSpacing / 2 }
    /// Masanın koridor tarafı: köylü beklerken burada ayakta durur.
    public func standSpot(for desk: OfficePlan.Desk) -> PlanPoint {
        PlanPoint(x: desk.x - outward * (deskHalfExtents.x + 0.35), z: desk.z)
    }

    /// Eşyalar (açık olanlar): koridor tarafındaki arka köşede ayaklı beyaz tahta (arka penceresi ve oda tabelası
    /// ortada), dış duvarın arka
    /// köşesinde kitaplık, ön tarafta dış duvar dibinde koltuk (önünde sehpa, arkasında saksı) ve dış köşede
    /// arcade, koridor tarafındaki ön köşede sebil ve kahve makinesi.
    public var spots: [RoomSpot] {
        let outer = corridorEdgeX + outward * width
        let inward = outward > 0 ? -Double.pi / 2 : Double.pi / 2
        let all = [
            RoomSpot(kind: .sofa, x: outer - outward * 0.45, z: z + 4.95, facing: inward),
            RoomSpot(kind: .coffeeTable, x: outer - outward * 1.25, z: z + 5.75, facing: 0),
            RoomSpot(kind: .plant, x: outer - outward * 0.4, z: z + 3.95, facing: 0),
            RoomSpot(kind: .waterCooler, x: corridorEdgeX + outward * 0.4, z: z + 5.75, facing: -inward),
            RoomSpot(kind: .coffeeMachine, x: corridorEdgeX + outward * 0.35, z: z + 6.75, facing: -inward),
            RoomSpot(kind: .arcade, x: outer - outward * 0.35, z: z + 6.8, facing: inward),
            RoomSpot(kind: .bookshelf, x: outer - outward * 0.17, z: z + 0.75, facing: inward),
            RoomSpot(kind: .whiteboard, x: corridorEdgeX + outward * 0.85, z: z + 0.3, facing: 0),
        ]
        return all.filter { furniture.contains($0.kind.furniture) }
    }
}

/// Yürüme hızı (m/sn); yol `RoomNav`'dan gelir (v5 aşama 2).
public enum AvatarRoute {
    public static let speed = 1.4
}


extension PlanRect {
    /// Negatif değer dikdörtgeni büyütür.
    func insetBy(_ amount: Double) -> PlanRect {
        PlanRect(minX: minX + amount, minZ: minZ + amount, maxX: maxX - amount, maxZ: maxZ - amount)
    }
}
