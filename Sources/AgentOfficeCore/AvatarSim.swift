import Foundation
import simd

public struct AvatarDeskState: Equatable, Sendable {
    public var state: AgentState
    public var kind: SessionKind
    /// İş bitti ve kullanıcı henüz görmedi (geçişte bir kez sevinç).
    public var unseenFinish: Bool
    public init(state: AgentState, kind: SessionKind, unseenFinish: Bool = false) {
        self.state = state; self.kind = kind; self.unseenFinish = unseenFinish
    }
}

/// Köylüler (v5 spec §5): her köylünün `AvatarBehavior`'ı ne yapacağına karar verir; burada uygulanır.
/// - Hedef: yol (`RoomNav`), yürüme, varınca oturma geçişi (`sitDown`), tek seferlik hareket ve döngü.
/// - Oturan köylü yeni bir hedef için önce kalkar (`standUp`).
/// - İlgi noktaları oda başına rezerve edilir: iki köylü aynı noktayı seçmez.
/// İlk yükleme yerinde başlar; sonrası canlıdır (yeni köylü kapıdan girer). Çizim thread'inde yaşar.
public struct AvatarSim: Sendable {
    /// Gidilen yer ve orada yapılacaklar.
    struct Target: Sendable {
        var point: PlanPoint
        var facing: Double
        var loop: AvatarClip
        var oneShot: AvatarClip?
        /// Oturulacak nokta (tabure ya da koltuk): varınca `sitDown` sırasında buraya kayılır.
        var seat: PlanPoint?
        var leave = false
    }

    /// Süren hareket: geçiş ya da tek seferlik klip; bitince ne olacağı.
    enum Action: Sendable {
        case standUp(remaining: Double, then: Target)
        case sitDown(remaining: Double, from: PlanPoint, to: PlanPoint, loop: AvatarClip, oneShot: AvatarClip?)
        case oneShot(remaining: Double, loop: AvatarClip)
    }

    struct Avatar: Sendable {
        var instance: AvatarInstance
        var behavior: AvatarBehavior
        var activity: AvatarActivity
        var unseenFinish: Bool
        var desk: OfficePlan.Desk
        var room: OfficePlan.Room
        var point: PlanPoint
        var path: [PlanPoint] = []
        var goal: AvatarGoal?
        var target: Target?
        var action: Action?
        /// Şu an oynanamayan tek seferlik hareket (ör. kalkarken gelen sevinç): varınca oynar.
        var pendingShot: AvatarClip?
        var seated = false
        var spot: RoomSpot.Kind?
    }

    public let skeleton: VillagerSkeleton
    private var avatars: [String: Avatar] = [:]
    private var navs: [String: RoomNav] = [:]
    public private(set) var clock: Double = 0
    public private(set) var instances: [AvatarInstance] = []
    /// Köylü → rezerve ettiği ilgi noktası (aynı odada ikinci bir köylü seçemez).
    public var reservedSpots: [String: RoomSpot.Kind] { avatars.compactMapValues(\.spot) }
    /// Bugüne kadar kaç kez nokta rezerve edildi (testler için).
    public private(set) var everReservedCount = 0

    public init(skeleton: VillagerSkeleton) {
        self.skeleton = skeleton
    }

    /// Yürüyen, geçiş ya da tek seferlik klip oynatan köylü var mı.
    public var isMoving: Bool { isWalking || isActing }
    /// Yürüyen köylü var mı (native kare hızı).
    public var isWalking: Bool { avatars.values.contains { !$0.path.isEmpty } }
    /// Yerinde tek seferlik hareket, oturma ya da kalkma oynatan köylü var mı (30 fps).
    public var isActing: Bool { avatars.values.contains { $0.action != nil } }

    // MARK: - Durum

    public mutating func sync(plan: OfficePlan, desks: [String: AvatarDeskState], looks: [String: AvatarLook],
                              projectColors: [String: AvatarLook.RGBA], live: Bool) {
        var seen = Set<String>()
        navs = Dictionary(uniqueKeysWithValues: plan.rooms.map { ($0.key, RoomNav(room: $0)) })
        for room in plan.rooms {
            let projectColor = projectColors[room.key] ?? (0.6, 0.6, 0.6)
            for desk in room.desks {
                guard let info = desks[desk.id] else { continue }
                let activity = AvatarActivity.hasAvatar(kind: info.kind, state: info.state)
                    ? AvatarActivity.for(state: info.state) : .away
                let existing = avatars[desk.id]
                if existing == nil, activity == .away { continue }
                seen.insert(desk.id)
                let look = looks[desk.id] ?? AvatarLook.default(for: desk.id)
                let shirt = look.shirtColor.map { AvatarLook.shirtColors[$0 % AvatarLook.shirtColors.count] } ?? projectColor
                var avatar = existing ?? Avatar(instance: AvatarInstance(id: desk.id, clip: .idle, look: look),
                                                behavior: AvatarBehavior(id: desk.id), activity: activity,
                                                unseenFinish: info.unseenFinish, desk: desk, room: room,
                                                point: room.doorOutside)
                if existing == nil { avatar.instance.position = Self.position(room.doorOutside) }
                avatar.instance.look = look
                avatar.instance.shirtColor = SIMD3(Float(shirt.red), Float(shirt.green), Float(shirt.blue))
                avatar.instance.waving = activity == .waving
                let finishedNow = info.unseenFinish && !(existing?.unseenFinish ?? true)
                let moved = existing.map { $0.room.key != room.key || $0.room.corridorEdgeX != room.corridorEdgeX
                    || $0.room.z != room.z || $0.desk != desk } ?? false
                let roomChanged = existing.map { $0.room != room } ?? false
                avatar.unseenFinish = info.unseenFinish
                avatar.desk = desk
                avatar.room = room
                if existing == nil || activity != avatar.activity || finishedNow {
                    avatar.activity = activity
                    avatar.behavior.setActivity(activity, finishedNow: finishedNow)
                }
                avatars[desk.id] = avatar
                if existing == nil {
                    // İlk karar hemen: canlıysa kapıdan yürür, değilse yerinde başlar.
                    decide(desk.id, dt: 0, place: !live)
                } else if moved {
                    // Masa ya da oda kaydı: yeni hedefe ışınla (odalar arası yürüme yok).
                    avatars[desk.id]?.target = nil
                    decide(desk.id, dt: 0, place: true, force: true)
                } else if roomChanged {
                    // Oda büyüdü: masalar yerinde ama dinlenme köşesi dışa kaydı. Yürüyorsa yol yeniden planlanır;
                    // bir noktada duruyorsa noktanın yeni yerine geçer (eski yer artık bir masanın içinde olabilir).
                    if avatars[desk.id]?.path.isEmpty == false {
                        replan(desk.id)
                    } else if case .spot = avatars[desk.id]?.goal {
                        decide(desk.id, dt: 0, place: true, force: true)
                    }
                }
            }
        }
        for id in avatars.keys where !seen.contains(id) { avatars[id] = nil }
        publish()
    }

    // MARK: - Zaman

    public mutating func tick(dt: Double) {
        clock += dt
        for id in avatars.keys.sorted() {
            guard avatars[id] != nil else { continue }
            decide(id, dt: dt, place: false)
            guard avatars[id] != nil else { continue }
            step(id, dt: dt)
        }
        publish()
    }

    /// Davranıştan kararı al ve uygula.
    private mutating func decide(_ id: String, dt: Double, place: Bool, force: Bool = false) {
        guard var avatar = avatars[id] else { return }
        let free = freeSpots(for: id, in: avatar.room)
        var decision = avatar.behavior.advance(dt: dt, freeSpots: free)
        if decision == nil, force, let goal = avatar.goal {
            // Zorla yeniden yerleştirme: son hedef, yeni masa ve oda yerine göre.
            avatars[id] = avatar
            apply(target(for: goal, avatar: avatar), to: id, place: true)
            return
        }
        avatars[id] = avatar
        guard let d = decision else { return }
        switch d {
        case .goal(let goal):
            avatar = avatars[id]!
            avatar.spot = nil
            avatar.goal = goal
            if case .spot(let kind, _, _, _) = goal {
                avatar.spot = kind
                everReservedCount += 1
            }
            avatars[id] = avatar
            apply(target(for: goal, avatar: avatar), to: id, place: place)
        case .oneShot(let clip):
            avatar = avatars[id]!
            // Yürürken ya da başka bir hareketin ortasında değilse.
            guard avatar.path.isEmpty, avatar.action == nil, avatar.target != nil else {
                // Yürürken ya da kalkarken: sevinç gibi önemli hareketler varınca oynar.
                if clip == .cheer { avatar.pendingShot = clip; avatars[id] = avatar }
                return
            }
            if clip.seated != avatar.seated && clip != .cheer { return }
            avatar.action = .oneShot(remaining: clip.duration, loop: avatar.target?.loop ?? .idle)
            avatar.instance.play(clip, skeleton: skeleton)
            avatars[id] = avatar
        }
        decision = nil
    }

    private func freeSpots(for id: String, in room: OfficePlan.Room) -> [RoomSpot.Kind] {
        let taken = Set(avatars.filter { $0.key != id && $0.value.room.key == room.key }.compactMap(\.value.spot))
        return room.spots.map(\.kind).filter { !taken.contains($0) }
    }

    private func target(for goal: AvatarGoal, avatar: Avatar) -> Target {
        let room = avatar.room, desk = avatar.desk
        switch goal {
        case .seat(let loop):
            return Target(point: room.seat(for: desk), facing: 0, loop: loop, seat: room.seat(for: desk))
        case .stand(let loop):
            return Target(point: room.standSpot(for: desk), facing: 0, loop: loop)
        case .spot(let kind, let loop, let oneShot, _):
            guard let spot = room.spots.first(where: { $0.kind == kind }) else {
                return Target(point: room.seat(for: desk), facing: 0, loop: .sitDoze, seat: room.seat(for: desk))
            }
            let a = room.approach(to: spot)
            return Target(point: a.stand, facing: a.facing, loop: loop ?? .idle, oneShot: oneShot, seat: a.seat)
        case .leave:
            return Target(point: room.doorOutside, facing: 0, loop: .idle, leave: true)
        }
    }

    /// Hedefi uygula: yerleştir (ilk yükleme, ışınlama) ya da (gerekirse kalkıp) yürü.
    private mutating func apply(_ target: Target, to id: String, place: Bool) {
        guard var avatar = avatars[id] else { return }
        avatar.target = target
        avatar.path = []
        if place {
            if target.leave { avatars[id] = nil; return }
            avatar.action = nil
            avatar.point = target.seat ?? target.point
            avatar.seated = target.seat != nil
            avatar.instance.facing = Float(target.facing)
            avatar.instance.position = Self.position(avatar.point)
            avatar.instance.play(target.loop, skeleton: skeleton)
            avatars[id] = avatar
            return
        }
        if avatar.seated {
            // Önce kalk; yürüyüş `standUp` bitince başlar.
            avatar.action = .standUp(remaining: AvatarClip.standUp.duration, then: target)
            avatar.instance.play(.standUp, skeleton: skeleton)
            avatars[id] = avatar
            return
        }
        avatar.action = nil
        avatars[id] = avatar
        startWalking(id, to: target)
    }

    private mutating func startWalking(_ id: String, to target: Target) {
        guard var avatar = avatars[id] else { return }
        avatar.seated = false
        var path: [PlanPoint] = [avatar.point]
        let room = avatar.room
        let nav = navs[room.key] ?? RoomNav(room: room)
        if avatar.point == room.doorOutside {
            // Kapıdan içeri gir.
            path.append(room.doorInside)
        }
        let from = path.last!
        let goal = target.leave ? room.doorInside : target.point
        path += (nav.path(from: from, to: goal) ?? [from, goal]).dropFirst()
        if target.leave { path.append(room.doorOutside) }
        // Ardışık aynı noktaları at.
        path = path.reduce(into: []) { result, p in
            if let last = result.last, last.distance(to: p) < 0.01 { return }
            result.append(p)
        }
        avatar.path = Array(path.dropFirst())
        avatar.target = target
        if avatar.path.isEmpty {
            avatars[id] = avatar
            arrive(id)
            return
        }
        avatar.instance.play(.walk, skeleton: skeleton)
        avatars[id] = avatar
    }

    /// Yürürken oda değişti: yolu bulunulan yerden yeniden planla.
    private mutating func replan(_ id: String) {
        guard let avatar = avatars[id], !avatar.path.isEmpty, let target = avatar.target else { return }
        startWalking(id, to: target)
    }

    private mutating func arrive(_ id: String) {
        guard var avatar = avatars[id], let target = avatar.target else { return }
        if target.leave { avatars[id] = nil; return }
        avatar.instance.facing = Float(target.facing)
        if let seat = target.seat {
            avatar.action = .sitDown(remaining: AvatarClip.sitDown.duration, from: avatar.point, to: seat,
                                     loop: target.loop, oneShot: target.oneShot)
            avatar.instance.play(.sitDown, skeleton: skeleton)
        } else if let shot = avatar.pendingShot ?? target.oneShot {
            avatar.pendingShot = nil
            avatar.action = .oneShot(remaining: shot.duration, loop: target.loop)
            avatar.instance.play(shot, skeleton: skeleton)
        } else {
            avatar.instance.play(target.loop, skeleton: skeleton)
        }
        avatars[id] = avatar
    }

    /// Bir köylünün yürüyüşünü ve süren hareketini ilerlet.
    private mutating func step(_ id: String, dt: Double) {
        guard var avatar = avatars[id] else { return }
        avatar.instance.advance(dt: dt)
        if let action = avatar.action {
            switch action {
            case .standUp(let remaining, let then):
                let left = remaining - dt
                if left > 0 {
                    avatar.action = .standUp(remaining: left, then: then)
                } else {
                    avatar.action = nil
                    avatar.seated = false
                    avatars[id] = avatar
                    startWalking(id, to: then)
                    return
                }
            case .sitDown(let remaining, let from, let to, let loop, let oneShot):
                let left = remaining - dt
                let t = 1 - max(left, 0) / AvatarClip.sitDown.duration
                avatar.point = PlanPoint(x: from.x + (to.x - from.x) * t, z: from.z + (to.z - from.z) * t)
                avatar.instance.position = Self.position(avatar.point)
                if left > 0 {
                    avatar.action = .sitDown(remaining: left, from: from, to: to, loop: loop, oneShot: oneShot)
                } else {
                    avatar.seated = true
                    if let shot = oneShot {
                        avatar.action = .oneShot(remaining: shot.duration, loop: loop)
                        avatar.instance.play(shot, skeleton: skeleton)
                    } else {
                        avatar.action = nil
                        avatar.instance.play(loop, skeleton: skeleton)
                    }
                }
            case .oneShot(let remaining, let loop):
                let left = remaining - dt
                if left > 0 {
                    avatar.action = .oneShot(remaining: left, loop: loop)
                } else {
                    avatar.action = nil
                    avatar.instance.play(loop, skeleton: skeleton)
                }
            }
            avatars[id] = avatar
            return
        }
        guard !avatar.path.isEmpty else { avatars[id] = avatar; return }
        var budget = AvatarRoute.speed * dt
        while budget > 0, let next = avatar.path.first {
            let dx = next.x - avatar.point.x, dz = next.z - avatar.point.z
            let distance = hypot(dx, dz)
            if distance > 0.001 { avatar.instance.facing = Float(atan2(dx, dz)) }
            if distance <= budget {
                avatar.point = next
                avatar.path.removeFirst()
                budget -= distance
            } else {
                avatar.point = PlanPoint(x: avatar.point.x + dx / distance * budget, z: avatar.point.z + dz / distance * budget)
                budget = 0
            }
        }
        avatar.instance.position = Self.position(avatar.point)
        avatars[id] = avatar
        if avatar.path.isEmpty { arrive(id) }
    }

    private mutating func publish() {
        instances = avatars.keys.sorted().compactMap { avatars[$0]?.instance }
    }

    static func position(_ p: PlanPoint) -> SIMD3<Float> { SIMD3(Float(p.x), 0, Float(p.z)) }
}
