import AgentOfficeCore
import AppKit
import RealityKit

/// Köylüye görünüşü uygular (spec §4): seçilmeyen saç ve gözlük örnekleri mesh'ten çıkarılır (birleşim başına bir
/// kez, önbellekli), tişört / ten / saç malzemeleri taban renkleriyle tanınıp yenisiyle değiştirilir.
@MainActor
final class AvatarAppearance {
    /// Blender'daki taban renkleri (`tools/office-art/build_assets.py` sözleşmesi); USD'den doğrusal değerler gelir.
    private static let shirtKey = [0.30, 0.55, 0.95]
    private static let skinKey = [0.99, 0.84, 0.72]
    private static let hairKey = [0.35, 0.20, 0.10]
    private static let hairInstances: [AvatarLook.HairStyle: String] = [
        .short: "HairShort", .pigtails: "HairPigtails", .spiky: "HairSpiky", .bob: "HairBob",
    ]

    private let textures: OfficeTextures
    private let baseMesh: MeshResource?
    private let baseMaterials: [any RealityKit.Material]
    private var meshes: [String: MeshResource] = [:]

    init(template: Entity, textures: OfficeTextures) {
        self.textures = textures
        let model = template.firstModelEntity()?.components[ModelComponent.self]
        baseMesh = model?.mesh
        baseMaterials = model?.materials ?? []
    }

    func apply(_ look: AvatarLook, projectColor: AvatarLook.RGBA, to villager: Entity) {
        guard let target = villager.firstModelEntity(), var model = target.components[ModelComponent.self],
              let mesh = mesh(hair: look.hairStyle, glasses: look.glasses) else { return }
        model.mesh = mesh
        let shirtColor = look.shirtColor.map { AvatarLook.shirtColors[$0] } ?? projectColor
        model.materials = baseMaterials.map { material in
            guard var pbr = material as? PhysicallyBasedMaterial else { return material }
            let key = pbr.baseColor.tint.cgColor.components?.prefix(3).map(Double.init) ?? []
            if Self.matches(key, Self.shirtKey) {
                pbr.baseColor = .init(tint: OfficeTextures.color(shirtColor), texture: .init(textures.shirt(look.shirtPattern)))
            } else if Self.matches(key, Self.skinKey) {
                pbr.baseColor.tint = OfficeTextures.linearColor(AvatarLook.skinTones[look.skin])
            } else if Self.matches(key, Self.hairKey) {
                pbr.baseColor.tint = OfficeTextures.linearColor(AvatarLook.hairColors[look.hairColor])
            }
            return pbr
        }
        target.components.set(model)
    }

    private static func matches(_ a: [Double], _ b: [Double]) -> Bool {
        a.count == 3 && zip(a, b).allSatisfy { abs($0 - $1) < 0.02 }
    }

    /// Sadece seçilen saç modeli (ve istenirse gözlük) kalan mesh.
    private func mesh(hair: AvatarLook.HairStyle, glasses: Bool) -> MeshResource? {
        let key = "\(hair.rawValue)-\(glasses)"
        if let cached = meshes[key] { return cached }
        guard let baseMesh else { return nil }
        var contents = baseMesh.contents
        let keep = Self.hairInstances[hair] ?? "HairShort"
        let drop = Self.hairInstances.values.filter { $0 != keep } + (glasses ? [] : ["Glasses"])
        for instance in contents.instances where drop.contains(where: { instance.id.hasPrefix($0) }) {
            _ = contents.instances.remove(id: instance.id)
        }
        do {
            let mesh = try MeshResource.generate(from: contents)
            meshes[key] = mesh
            return mesh
        } catch {
            DebugLog.write("avatar mesh \(key) failed: \(error)")
            return baseMesh
        }
    }
}
