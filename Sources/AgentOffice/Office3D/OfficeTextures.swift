import AgentOfficeCore
import AppKit
import RealityKit

/// RealityKit malzemeleri; desenler `OfficePatterns`'tan.
@MainActor
final class OfficeTextures {
    private var cache: [String: TextureResource] = [:]

    // MARK: - Malzemeler

    /// Döşenen dokulu malzeme: `repeats` kaç kez tekrar edeceği (yüzey başına).
    func material(_ texture: TextureResource?, tint: NSColor = .white, repeats: SIMD2<Float> = [1, 1],
                  roughness: Float = 0.8) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        if let texture {
            var sampler = MaterialParameters.Texture.Sampler()
            sampler.modify { descriptor in
                descriptor.sAddressMode = .repeat
                descriptor.tAddressMode = .repeat
                descriptor.minFilter = .linear
                descriptor.magFilter = .linear
                descriptor.mipFilter = .linear
            }
            material.baseColor = .init(tint: tint, texture: .init(texture, sampler: sampler))
            material.textureCoordinateTransform = .init(offset: .zero, scale: repeats, rotation: 0)
        } else {
            material.baseColor = .init(tint: tint)
        }
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0)
        return material
    }

    static func color(_ c: AvatarLook.RGBA) -> NSColor {
        NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    /// Blender'dan gelen malzemelerle aynı (doğrusal) uzayda renk: köylünün ten ve saç tonları modeldeki gibi görünsün.
    static func linearColor(_ c: AvatarLook.RGBA) -> NSColor {
        let space = NSColorSpace(cgColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)!
        return NSColor(colorSpace: space, components: [c.red, c.green, c.blue, 1], count: 4)
    }

    // MARK: - Dokular

    func floor(_ index: Int) -> TextureResource { texture(OfficeTextureLayer.floor(index)) }
    func wallpaper(_ index: Int) -> TextureResource { texture(OfficeTextureLayer.wallpaper(index)) }
    var wainscot: TextureResource { texture(OfficeTextureLayer.wainscot) }
    func rug(_ pattern: RoomStyle.RugPattern) -> TextureResource { texture(OfficeTextureLayer.rug(pattern)) }
    func shirt(_ pattern: AvatarLook.ShirtPattern) -> TextureResource { texture(OfficeTextureLayer.shirt(pattern)) }
    var grass: TextureResource { texture(OfficeTextureLayer.grass) }
    var dirt: TextureResource { texture(OfficeTextureLayer.dirt) }
    var path: TextureResource { texture(OfficeTextureLayer.path) }

    private func texture(_ layer: UInt16) -> TextureResource {
        let key = "layer\(layer)"
        if let cached = cache[key] { return cached }
        let image = OfficePatterns.image(layer: Int(layer))
        let resource: TextureResource
        do {
            resource = try TextureResource.generate(from: image, withName: key,
                                                    options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
        } catch {
            DebugLog.write("texture \(key) failed: \(error)")
            resource = try! TextureResource.generate(from: image, options: .init(semantic: .color))
        }
        cache[key] = resource
        return resource
    }
}
