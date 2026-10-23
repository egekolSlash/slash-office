import Foundation
import simd

/// Ofiste bir minyonun bu karedeki hâli (çizim ve poz için).
public struct MinionInstance: Equatable, Sendable {
    public enum Motion: Equatable, Sendable {
        /// Yerde yürüyor; `cycle` adım döngüsü (1 = tam adım çifti).
        case walk(cycle: Float)
        case idle
        /// Bilgisayardan çıkış ya da bilgisayara dalış yayında.
        case air
    }

    public var id: String
    public var position: SIMD3<Float>
    /// y ekseni etrafında radyan, 0 = +z (köylülerle aynı).
    public var facing: Float
    public var scale: Float
    public var motion: Motion
    /// Minyonun kendi saati (bekleme salınımları için).
    public var time: Float
    /// Kişisel faz (sabit tohumdan): minyonlar aynı anda aynı hareketi yapmasın.
    public var seed: Float
}

/// Arka plan işi minyonları (spec §6): her iş için agent'ın masasında bir kedi. İş başlayınca masadaki bilgisayardan
/// yay çizerek masanın yanına atlar, masanın çevresindeki halkada dolaşır (ara sıra durur, bazen döner); iş bitince yan
/// noktaya yürür ve bilgisayara geri dalar. Masa başına en çok `maxPerDesk`. Rastgelelik iş kimliğinden: deterministik.
public struct MinionSim: Sendable {
    public static let maxPerDesk = 4
    static let speed = 0.32
    static let stride = 0.11
    static let popDuration = 0.8
    static let diveDuration = 0.7
    static let arcHeight = 0.32
    /// Masa takımındaki ekranın yerel konumu (masa yerel uzayı: x uzun kenar, +z köylünün baktığı yön, y yukarı).
    static let screenLocal = SIMD3<Double>(0, 0.70, 0.09)
    /// Halka: masanın çevresinde, taburedeki köylünün arkasından geçecek kadar geniş.
    static let ringMargin = 0.30
    static var ringX: Double { DeskGeometry.deskHalfDepth + ringMargin }
    static var ringZMin: Double { -(DeskGeometry.seatOffset + ringMargin) }
    static var ringZMax: Double { DeskGeometry.deskHalfWidth + ringMargin }

    struct Desk: Equatable, Sendable {
        var x: Double
        var z: Double
        var yaw: Double

        func world(_ local: SIMD3<Double>) -> SIMD3<Float> {
            let c = cos(yaw), s = sin(yaw)
            return SIMD3(Float(x + local.x * c + local.z * s), Float(local.y), Float(z - local.x * s + local.z * c))
        }
    }

    enum Phase: Equatable, Sendable {
        case hidden(delay: Double)
        case pop
        case walk(left: Double)
        case idle(left: Double)
        case toExit
        case dive
    }

    struct Minion: Sendable {
        var key: String
        var session: String
        var job: String
        var slot: Int
        var phase: Phase
        var t = 0.0
        /// Halka üzerindeki konum (çevre uzunluğu boyunca, metre) ve yön (+1 / −1).
        var s: Double
        var dir: Double
        var distance = 0.0
        var clock = 0.0
        var rng: UInt64
        var seed: Float

        /// Bu minyonun çıkıp girdiği yan (+1: masanın yerel +x yanı).
        var side: Double { slot % 2 == 0 ? 1 : -1 }

        mutating func random() -> Double {
            rng &+= 0x9e3779b97f4a7c15
            var z = rng
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
        }
    }

    private var desks: [String: Desk] = [:]
    private var jobs: [String: [String]] = [:]
    private(set) var minions: [Minion] = []

    public init() {}

    /// Masa başına iş listesi (oturum → iş kimlikleri, başlama sırasıyla). Planda masası olmayan oturum yok sayılır.
    public mutating func sync(plan: OfficePlan, jobs: [String: [String]]) {
        var desks: [String: Desk] = [:]
        for room in plan.rooms {
            for desk in room.desks { desks[desk.id] = Desk(x: desk.x, z: desk.z, yaw: room.seatFacing(for: desk)) }
        }
        self.desks = desks
        self.jobs = jobs.filter { desks[$0.key] != nil }.mapValues { Array($0.prefix(Self.maxPerDesk)) }
        // Masası gidenler hemen kalkar; işi bitenler çıkışa yürür.
        minions.removeAll { desks[$0.session] == nil }
        for i in minions.indices where !(self.jobs[minions[i].session] ?? []).contains(minions[i].job) {
            switch minions[i].phase {
            case .hidden: minions[i].phase = .dive; minions[i].t = Self.diveDuration
            case .pop, .walk, .idle: minions[i].phase = .toExit
            case .toExit, .dive: break
            }
        }
        for (session, list) in self.jobs {
            for job in list where !minions.contains(where: { $0.session == session && $0.job == job && !$0.leaving }) {
                let used = Set(minions.filter { $0.session == session }.map(\.slot))
                guard let slot = (0..<Self.maxPerDesk).first(where: { !used.contains($0) }) else { continue }
                let pending = minions.filter { m in
                    guard m.session == session else { return false }
                    if case .hidden = m.phase { return true }
                    return m.phase == .pop
                }.count
                let key = session + "/" + job
                let hash = StableHash.mixed(key)
                let side: Double = slot % 2 == 0 ? 1 : -1
                minions.append(Minion(key: key, session: session, job: job, slot: slot, phase: .hidden(delay: 0.35 * Double(pending)),
                                      s: Self.ringS(local: (side * Self.ringX, 0)), dir: side > 0 ? 1 : -1, rng: hash,
                                      seed: Float(hash % 1000) / 1000))
            }
        }
    }

    public mutating func tick(dt: Double) {
        for i in minions.indices { Self.advance(&minions[i], dt: dt) }
        minions.removeAll { $0.phase == .dive && $0.t >= Self.diveDuration }
    }

    public var instances: [MinionInstance] {
        minions.compactMap { m in desks[m.session].flatMap { Self.instance(m, desk: $0) } }
    }

    /// Yürüyen ya da havada minyon var (native kare hızı).
    public var isMoving: Bool {
        minions.contains {
            switch $0.phase {
            case .pop, .walk, .toExit, .dive: true
            default: false
            }
        }
    }

    public var isEmpty: Bool { minions.isEmpty }

    // MARK: - Durum makinesi

    static func advance(_ m: inout Minion, dt: Double) {
        m.clock += dt
        m.t += dt
        switch m.phase {
        case .hidden(let delay):
            if m.t >= delay { m.phase = .pop; m.t = 0 }
        case .pop:
            if m.t >= popDuration { m.phase = .walk(left: 1.5 + 3 * m.random()); m.t = 0 }
        case .walk(let left):
            move(&m, dt)
            if left - dt <= 0 {
                m.phase = .idle(left: 0.8 + 1.8 * m.random())
            } else {
                m.phase = .walk(left: left - dt)
            }
        case .idle(let left):
            if left - dt <= 0 {
                if m.random() < 0.35 { m.dir = -m.dir }
                m.phase = .walk(left: 2 + 3 * m.random())
            } else {
                m.phase = .idle(left: left - dt)
            }
        case .toExit:
            let exit = ringS(local: (m.side * ringX, 0))
            let delta = shortest(from: m.s, to: exit)
            let step = speed * dt
            if abs(delta) <= step {
                m.s = exit
                m.phase = .dive
                m.t = 0
            } else {
                m.dir = delta > 0 ? 1 : -1
                move(&m, dt)
            }
        case .dive:
            break
        }
    }

    static func move(_ m: inout Minion, _ dt: Double) {
        let step = speed * dt
        m.s = wrap(m.s + m.dir * step)
        m.distance += step
    }

    // MARK: - Halka (masa yerel uzayında dikdörtgen; çevre boyunca s)

    static var perimeter: Double { 4 * ringX + 2 * (ringZMax - ringZMin) }

    static func wrap(_ s: Double) -> Double {
        let p = perimeter
        let r = s.truncatingRemainder(dividingBy: p)
        return r < 0 ? r + p : r
    }

    static func shortest(from a: Double, to b: Double) -> Double {
        var d = wrap(b - a)
        if d > perimeter / 2 { d -= perimeter }
        return d
    }

    /// Kenarlar sırasıyla: +x kenarı (zMin → zMax), ön kenar (+x → −x), −x kenarı (zMax → zMin), arka kenar (−x → +x).
    static func ringPoint(_ s: Double) -> (x: Double, z: Double, dx: Double, dz: Double) {
        let depth = ringZMax - ringZMin, width = 2 * ringX
        var r = wrap(s)
        if r < depth { return (ringX, ringZMin + r, 0, 1) }
        r -= depth
        if r < width { return (ringX - r, ringZMax, -1, 0) }
        r -= width
        if r < depth { return (-ringX, ringZMax - r, 0, -1) }
        r -= depth
        return (-ringX + r, ringZMin, 1, 0)
    }

    /// Halkadaki bir noktanın s değeri (nokta kenar üzerinde olmalı).
    static func ringS(local p: (Double, Double)) -> Double {
        let depth = ringZMax - ringZMin, width = 2 * ringX
        let (x, z) = p
        if abs(x - ringX) < 1e-9 { return z - ringZMin }
        if abs(z - ringZMax) < 1e-9 { return depth + (ringX - x) }
        if abs(x + ringX) < 1e-9 { return depth + width + (ringZMax - z) }
        return 2 * depth + width + (x + ringX)
    }

    // MARK: - Çizim hâli

    static func instance(_ m: Minion, desk: Desk) -> MinionInstance? {
        let landing = SIMD3<Double>(m.side * ringX, 0, 0)
        func arc(_ u: Double) -> SIMD3<Double> {
            let u = min(max(u, 0), 1)
            var p = screenLocal + (landing - screenLocal) * u
            p.y += 4 * arcHeight * u * (1 - u)
            return p
        }
        let sideFacing = m.side > 0 ? Double.pi / 2 : -Double.pi / 2
        let local: SIMD3<Double>
        var facing: Double
        var scale = 1.0
        var motion: MinionInstance.Motion
        switch m.phase {
        case .hidden:
            return nil
        case .pop:
            let u = m.t / popDuration
            local = arc(u)
            facing = sideFacing
            scale = min(1, 0.25 + 0.75 * u / 0.35)
            motion = .air
        case .dive:
            let u = 1 - m.t / diveDuration
            local = arc(u)
            facing = sideFacing + .pi
            scale = u > 0.4 ? 1 : max(0.05, u / 0.4)
            motion = .air
        case .walk, .toExit, .idle:
            let p = ringPoint(m.s)
            local = SIMD3(p.x, 0, p.z)
            facing = atan2(p.dx * m.dir, p.dz * m.dir)
            if case .idle = m.phase {
                // Dururken masadan dışarı (çoğunlukla kameraya) döner: yüzü görünsün.
                facing = atan2(p.x, p.z)
                motion = .idle
            } else {
                motion = .walk(cycle: Float(m.distance / (2 * stride)))
            }
        }
        return MinionInstance(id: m.key, position: desk.world(local), facing: Float(facing + desk.yaw), scale: Float(scale),
                              motion: motion, time: Float(m.clock), seed: m.seed)
    }
}

extension MinionSim.Minion {
    var leaving: Bool {
        switch phase {
        case .toExit, .dive: true
        default: false
        }
    }
}

/// Minyonun kemik matrisleri (`MinionArt` sırası: body, head, leg_L, leg_R, tail): katı parçalar pivotları etrafında
/// döner. Yürürken bacaklar zıt sallanır, gövde zıplar ve yalpalar; dururken nefes, baş bakınır, kuyruk sallanır;
/// havada bacaklar toplanır.
public enum MinionPose {
    public static func bones(for m: MinionInstance, pivots: [SIMD3<Float>]) -> [simd_float4x4] {
        guard pivots.count == 5 else { return Array(repeating: matrix_identity_float4x4, count: pivots.count) }
        var bodyLift: Float = 0, bodyRoll: Float = 0, bodyPitch: Float = 0
        var headYaw: Float = 0, headPitch: Float = 0
        var legL: Float = 0, legR: Float = 0
        var tailYaw: Float = 0, tailPitch: Float = 0
        let t = m.time + m.seed * 10
        switch m.motion {
        case .walk(let cycle):
            let c = cycle * 2 * .pi
            bodyLift = 0.012 * abs(sin(c))
            bodyRoll = 0.07 * sin(c)
            legL = 0.55 * sin(c)
            legR = -0.55 * sin(c)
            headPitch = 0.05 * sin(2 * c)
            tailYaw = 0.3 * sin(c * 0.5)
        case .idle:
            bodyLift = 0.004 * sin(t * 2)
            headYaw = 0.3 * sin(t * 0.7)
            headPitch = 0.04 * sin(t * 1.3)
            tailYaw = 0.45 * sin(t * 2.6)
        case .air:
            bodyPitch = -0.15
            legL = -0.6
            legR = -0.6
            tailPitch = -0.4
        }
        let body = translation(SIMD3(0, bodyLift, 0)) * about(pivots[0], rotation(x: bodyPitch, y: 0, z: bodyRoll))
        return [
            body,
            body * about(pivots[1], rotation(x: headPitch, y: headYaw, z: 0)),
            body * about(pivots[2], rotation(x: legL, y: 0, z: 0)),
            body * about(pivots[3], rotation(x: legR, y: 0, z: 0)),
            body * about(pivots[4], rotation(x: tailPitch, y: tailYaw, z: 0)),
        ]
    }

    static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(t, 1)
        return m
    }

    static func rotation(x: Float, y: Float, z: Float) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: y, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: x, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: z, axis: SIMD3(0, 0, 1)))
    }

    /// `pivot` etrafında dönüş: T(p) · R · T(−p).
    static func about(_ pivot: SIMD3<Float>, _ r: simd_float4x4) -> simd_float4x4 {
        translation(pivot) * r * translation(-pivot)
    }
}
