import AgentOfficeCore
import Foundation
import RealityKit

/// Ofis varlıkları (spec §8): köylü şablonu, klipleri ve eşya şablonları. Bulunamazsa ofis sade görünüme düşer.
@MainActor
final class OfficeArt {
    static let propNames = ["desk_set", "terminal_set", "bookshelf", "plant", "lamp", "tree", "flower", "window", "curtain"]

    let villager: Entity
    let clips: [AvatarClip: AnimationResource]
    private let props: [String: Entity]

    private init(villager: Entity, clips: [AvatarClip: AnimationResource], props: [String: Entity]) {
        self.villager = villager
        self.clips = clips
        self.props = props
    }

    /// Önce uygulama paketi, sonra depo (paketsiz `swift run`).
    static func load() async -> OfficeArt? {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let dir = OfficeArtLocation.find(bundleResources: Bundle.main.resourceURL, repoRoot: repoRoot) else {
            DebugLog.write("office art not found; falling back to simple office")
            return nil
        }
        do {
            let villager = try await Entity(contentsOf: dir.appendingPathComponent("villager.usdz"))
            guard let base = firstAnimation(villager) else {
                DebugLog.write("office art: villager has no animation")
                return nil
            }
            var clips: [AvatarClip: AnimationResource] = [:]
            for clip in AvatarClip.allCases {
                // USD zaman çizelgesi 1. kareden başlar; 24 fps.
                let view = AnimationView(source: base.definition, name: clip.rawValue,
                                         trimStart: Double(clip.frames.lowerBound - 1) / 24,
                                         trimEnd: Double(clip.frames.upperBound - 1) / 24)
                clips[clip] = try AnimationResource.generate(with: view).repeat()
            }
            var props: [String: Entity] = [:]
            for name in propNames {
                props[name] = try await Entity(contentsOf: dir.appendingPathComponent("props/\(name).usdz"))
            }
            DebugLog.write("office art loaded from \(dir.path)")
            return OfficeArt(villager: villager, clips: clips, props: props)
        } catch {
            DebugLog.write("office art load failed: \(error)")
            return nil
        }
    }

    func prop(_ name: String) -> Entity {
        props[name]?.clone(recursive: true) ?? Entity()
    }

    private static func firstAnimation(_ entity: Entity) -> AnimationResource? {
        if let animation = entity.availableAnimations.first { return animation }
        for child in entity.children {
            if let animation = firstAnimation(child) { return animation }
        }
        return nil
    }
}

extension Entity {
    /// İlk `ModelComponent`'li alt varlık (USD'den gelen iskeletli model tek bir varlıkta birleşir).
    func firstModelEntity() -> Entity? {
        if components.has(ModelComponent.self) { return self }
        for child in children {
            if let found = child.firstModelEntity() { return found }
        }
        return nil
    }
}
