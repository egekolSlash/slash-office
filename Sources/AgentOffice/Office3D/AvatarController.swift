import AgentOfficeCore
import AppKit
import Foundation
import RealityKit

/// Köylüler (spec §5): kararlar Core'daki `AvatarPlanner`'dan gelir; burada uygulanır. Durum ya da masa
/// değişince yeniden planlanır; yürüyenler `tick` ile yol boyunca ilerler, varınca hedef klibe geçer.
@MainActor
final class AvatarController {
    let root = Entity()
    private let art: OfficeArt
    private let appearance: AvatarAppearance

    private final class Avatar {
        let entity: Entity
        var look: AvatarLook
        var color: [Double]
        var activity: AvatarActivity
        var desk: OfficePlan.Desk
        var roomKey: String
        var room: PlanRect = .zero
        /// Beklerken ayak altında nabız gibi atan turuncu halka (bekleyen ajan bir bakışta görünsün).
        let ring: ModelEntity
        var point: PlanPoint
        var path: [PlanPoint] = []
        var then: AvatarClip = .idle
        var facing: Double = 0
        var hideAtEnd = false
        var clip: AvatarClip?

        init(entity: Entity, look: AvatarLook, color: [Double], activity: AvatarActivity, desk: OfficePlan.Desk,
             roomKey: String, point: PlanPoint) {
            self.entity = entity; self.look = look; self.color = color; self.activity = activity
            self.desk = desk; self.roomKey = roomKey; self.point = point
            var material = UnlitMaterial(color: NSColor(red: 1.0, green: 0.6, blue: 0.15, alpha: 1))
            material.blending = .transparent(opacity: .init(floatLiteral: 0.85))
            ring = ModelEntity(mesh: .generateCylinder(height: 0.008, radius: 0.32), materials: [material])
            ring.position = [0, 0.012, 0]
            ring.isEnabled = false
            entity.addChild(ring)
        }
    }

    private var avatars: [String: Avatar] = [:]
    private var clock: Double = 0

    init(art: OfficeArt, appearance: AvatarAppearance) {
        self.art = art
        self.appearance = appearance
    }

    /// Yürüyen köylü var mı (kare hızı için).
    var isMoving: Bool { avatars.values.contains { !$0.path.isEmpty } }

    func sync(plan: OfficePlan, desks: [String: OfficeDeskInfo], look: (String) -> AvatarLook,
              projectColor: (String) -> AvatarLook.RGBA, live: Bool) {
        var seen = Set<String>()
        for room in plan.rooms {
            let c = projectColor(room.key)
            let color = [c.red, c.green, c.blue]
            for desk in room.desks {
                guard let info = desks[desk.id] else { continue }
                let activity = AvatarActivity.hasAvatar(kind: info.kind, state: info.state)
                    ? AvatarActivity.for(state: info.state) : .away
                let wantedLook = look(desk.id)
                let existing = avatars[desk.id]
                if existing == nil, activity == .away { continue }
                seen.insert(desk.id)
                let avatar: Avatar
                if let existing {
                    avatar = existing
                    if avatar.look != wantedLook || avatar.color != color {
                        appearance.apply(wantedLook, projectColor: c, to: avatar.entity)
                        avatar.look = wantedLook
                        avatar.color = color
                    }
                    // Aynı etkinlik, aynı masa: yeniden planlamaya gerek yok (yürüyorsa yürümeye devam eder).
                    if avatar.activity == activity, avatar.desk == desk, avatar.roomKey == room.key, avatar.room == room.rect { continue }
                } else {
                    let entity = art.villager.clone(recursive: true)
                    appearance.apply(wantedLook, projectColor: c, to: entity)
                    root.addChild(entity)
                    avatar = Avatar(entity: entity, look: wantedLook, color: color, activity: activity, desk: desk,
                                    roomKey: room.key, point: room.doorOutside)
                }
                let current = existing.map { AvatarPose(point: $0.point, roomKey: $0.roomKey, room: $0.room) }
                let step = AvatarPlanner.plan(current: current, activity: activity, desk: desk, room: room, live: live)
                avatar.activity = activity
                avatar.desk = desk
                avatar.roomKey = room.key
                avatar.room = room.rect
                avatar.ring.isEnabled = activity == .waving
                avatars[desk.id] = avatar
                apply(step, to: avatar, id: desk.id)
            }
        }
        for (id, avatar) in avatars where !seen.contains(id) {
            avatar.entity.removeFromParent()
            avatars[id] = nil
        }
    }

    private func apply(_ step: AvatarStep, to avatar: Avatar, id: String) {
        switch step {
        case .place(let point, let clip, let facing):
            avatar.path = []
            avatar.point = point
            avatar.entity.position = Self.position(point)
            avatar.entity.orientation = Self.rotation(facing)
            play(clip, on: avatar)
        case .walk(let path, let then, let facing, let hide):
            guard let first = path.first else { return }
            avatar.point = first
            avatar.entity.position = Self.position(first)
            avatar.path = Array(path.dropFirst())
            avatar.then = then
            avatar.facing = facing
            avatar.hideAtEnd = hide
            play(.walk, on: avatar)
        case .hide:
            avatar.entity.removeFromParent()
            avatars[id] = nil
        }
    }

    func tick(dt: Double) {
        clock += dt
        let pulse = Float(1 + 0.18 * sin(clock * 5))
        for avatar in avatars.values where avatar.ring.isEnabled { avatar.ring.scale = [pulse, 1, pulse] }
        for (id, avatar) in avatars where !avatar.path.isEmpty {
            var budget = AvatarRoute.speed * dt
            while budget > 0, let next = avatar.path.first {
                let dx = next.x - avatar.point.x, dz = next.z - avatar.point.z
                let distance = hypot(dx, dz)
                if distance > 0.001 { avatar.entity.orientation = Self.rotation(atan2(dx, dz)) }
                if distance <= budget {
                    avatar.point = next
                    avatar.path.removeFirst()
                    budget -= distance
                } else {
                    avatar.point = PlanPoint(x: avatar.point.x + dx / distance * budget, z: avatar.point.z + dz / distance * budget)
                    budget = 0
                }
            }
            avatar.entity.position = Self.position(avatar.point)
            if avatar.path.isEmpty {
                if avatar.hideAtEnd {
                    avatar.entity.removeFromParent()
                    avatars[id] = nil
                } else {
                    avatar.entity.orientation = Self.rotation(avatar.facing)
                    play(avatar.then, on: avatar)
                }
            }
        }
    }

    private func play(_ clip: AvatarClip, on avatar: Avatar) {
        guard avatar.clip != clip, let animation = art.clips[clip] else { return }
        avatar.entity.playAnimation(animation, transitionDuration: 0.25, startsPaused: false)
        avatar.clip = clip
    }

    private static func position(_ p: PlanPoint) -> SIMD3<Float> { [Float(p.x), 0, Float(p.z)] }

    /// Köylü varsayılan olarak +z'ye bakar; `angle` y ekseni etrafında.
    private static func rotation(_ angle: Double) -> simd_quatf { simd_quatf(angle: Float(angle), axis: [0, 1, 0]) }
}
