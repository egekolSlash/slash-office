import Foundation
import simd

public struct AvatarDeskState: Equatable, Sendable {
    public var state: AgentState
    public var kind: SessionKind
    public init(state: AgentState, kind: SessionKind) {
        self.state = state; self.kind = kind
    }
}

/// Köylüler (v3 spec §5, v4 spec §5): kararlar `AvatarPlanner`'dan; burada uygulanır. Durum ya da masa değişince
/// yeniden planlanır; yürüyenler `tick` ile yol boyunca ilerler, varınca hedef klibe geçer. Çizim thread'inde yaşar.
public struct AvatarSim: Sendable {
    struct Avatar: Sendable {
        var instance: AvatarInstance
        var activity: AvatarActivity
        var desk: OfficePlan.Desk
        var roomKey: String
        var room: PlanRect
        var point: PlanPoint
        var path: [PlanPoint] = []
        var then: AvatarClip = .idle
        var targetFacing: Double = 0
        var hideAtEnd = false
    }

    public let skeleton: VillagerSkeleton
    private var avatars: [String: Avatar] = [:]
    public private(set) var clock: Double = 0
    public private(set) var instances: [AvatarInstance] = []

    public init(skeleton: VillagerSkeleton) {
        self.skeleton = skeleton
    }

    /// Yürüyen köylü var mı (kare hızı için).
    public var isMoving: Bool { avatars.values.contains { !$0.path.isEmpty } }

    public mutating func sync(plan: OfficePlan, desks: [String: AvatarDeskState], looks: [String: AvatarLook],
                              projectColors: [String: AvatarLook.RGBA], live: Bool) {
        var seen = Set<String>()
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
                                                activity: activity, desk: desk, roomKey: room.key, room: room.rect,
                                                point: room.doorOutside)
                avatar.instance.look = look
                avatar.instance.shirtColor = SIMD3(Float(shirt.red), Float(shirt.green), Float(shirt.blue))
                // Aynı etkinlik, aynı masa: yeniden planlamaya gerek yok (yürüyorsa yürümeye devam eder).
                if let existing, existing.activity == activity, existing.desk == desk, existing.roomKey == room.key,
                   existing.room == room.rect {
                    avatars[desk.id] = avatar
                    continue
                }
                let current = existing.map { AvatarPose(point: $0.point, roomKey: $0.roomKey, room: $0.room) }
                let step = AvatarPlanner.plan(current: current, activity: activity, desk: desk, room: room, live: live)
                avatar.activity = activity
                avatar.desk = desk
                avatar.roomKey = room.key
                avatar.room = room.rect
                avatar.instance.waving = activity == .waving
                avatars[desk.id] = avatar
                apply(step, id: desk.id)
            }
        }
        for id in avatars.keys where !seen.contains(id) { avatars[id] = nil }
        publish()
    }

    private mutating func apply(_ step: AvatarStep, id: String) {
        guard var avatar = avatars[id] else { return }
        switch step {
        case .place(let point, let clip, let facing):
            avatar.path = []
            avatar.point = point
            avatar.instance.facing = Float(facing)
            avatar.instance.play(clip, skeleton: skeleton)
        case .walk(let path, let then, let facing, let hide):
            guard let first = path.first else { return }
            avatar.point = first
            avatar.path = Array(path.dropFirst())
            avatar.then = then
            avatar.targetFacing = facing
            avatar.hideAtEnd = hide
            avatar.instance.play(.walk, skeleton: skeleton)
        case .hide:
            avatars[id] = nil
            return
        }
        avatar.instance.position = Self.position(avatar.point)
        avatars[id] = avatar
    }

    public mutating func tick(dt: Double) {
        clock += dt
        for id in avatars.keys {
            guard var avatar = avatars[id] else { continue }
            avatar.instance.advance(dt: dt)
            if !avatar.path.isEmpty {
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
                if avatar.path.isEmpty {
                    if avatar.hideAtEnd {
                        avatars[id] = nil
                        continue
                    }
                    avatar.instance.facing = Float(avatar.targetFacing)
                    avatar.instance.play(avatar.then, skeleton: skeleton)
                }
            }
            avatars[id] = avatar
        }
        publish()
    }

    private mutating func publish() {
        instances = avatars.keys.sorted().compactMap { avatars[$0]?.instance }
    }

    static func position(_ p: PlanPoint) -> SIMD3<Float> { SIMD3(Float(p.x), 0, Float(p.z)) }
}
