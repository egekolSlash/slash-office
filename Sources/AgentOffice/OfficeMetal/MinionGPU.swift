import AgentOfficeCore
import Foundation
import Metal
import simd

/// Minyon çizimi (`MinionArt`): köylülerin boru hattıyla (`CharacterGPU.pipe`) çizilir; minyon başına parça başına
/// bir çizim, kemikleri bu karenin paletinde köylülerden sonra (minyon i: `boneBase + i × 5`).
final class MinionGPU: @unchecked Sendable {
    let art: MinionArt
    private let meshes: [String: CharacterGPU.MeshBuffers]
    private let textures: [String: MTLTexture]

    var boneCount: Int { art.bones.count }

    init(art: MinionArt, device: MTLDevice, queue: MTLCommandQueue) throws {
        self.art = art
        var meshes: [String: CharacterGPU.MeshBuffers] = [:]
        for (name, m) in art.meshes { meshes[name] = try CharacterGPU.upload(m, name: name, device: device) }
        self.meshes = meshes
        var textures: [String: MTLTexture] = [:]
        for path in Set(art.parts.compactMap(\.texture)) {
            if let t = CharacterGPU.loadTexture(art.directory.appendingPathComponent(path), device: device, queue: queue) {
                textures[path] = t
            } else {
                DebugLog.write("minion texture missing: \(path)")
            }
        }
        self.textures = textures
    }

    func bones(for minion: MinionInstance) -> [simd_float4x4] {
        MinionPose.bones(for: minion, pivots: art.pivots)
    }

    func items(for minions: [MinionInstance], boneBase: Int) -> [CharacterGPU.Item] {
        var out: [CharacterGPU.Item] = []
        for (i, m) in minions.enumerated() {
            var model = simd_float4x4(simd_quatf(angle: m.facing, axis: SIMD3(0, 1, 0)))
            model.columns.0 *= m.scale
            model.columns.1 *= m.scale
            model.columns.2 *= m.scale
            model.columns.3 = SIMD4(m.position, 1)
            for part in art.parts {
                guard let mesh = meshes[part.mesh] else { continue }
                let texture = part.texture.flatMap { textures[$0] }
                let color = part.color.map { SIMD3($0[0], $0[1], $0[2]) } ?? SIMD3<Float>(1, 1, 1)
                let code: Float = texture == nil ? 0 : (CharacterGPU.modeCode[part.mode] ?? 0)
                let draw = CharacterGPU.Draw(model: model, tint: SIMD4(color, code), boneBase: UInt32(boneBase + i * boneCount))
                out.append(CharacterGPU.Item(mesh: mesh, texture: texture, draw: draw))
            }
        }
        return out
    }
}
