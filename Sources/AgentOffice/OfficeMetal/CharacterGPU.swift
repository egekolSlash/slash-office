import AgentOfficeCore
import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

/// Karakter çizimi (`CharacterArt`): mesh'ler GPU'ya bir kez gider, dokular ilk kullanıldıklarında yüklenir. Köylü
/// başına parça başına bir çizim (her parçanın dokusu ve tonu farklı); bir ofiste ~10 köylü × ~10 parça.
final class CharacterGPU: @unchecked Sendable {
    struct Draw {
        var model: simd_float4x4
        /// rgb sRGB, w: mod (0 düz, 1 doku, 2 doku × ton, 3 çıkartma, 4 kesik).
        var tint: SIMD4<Float>
        var boneBase: UInt32
        var pad: (UInt32, UInt32, UInt32) = (0, 0, 0)
    }

    struct MeshBuffers {
        let vertices: MTLBuffer
        let indices: MTLBuffer
        let count: Int
    }

    /// Kare başına çizim listesi: mesh, doku (yoksa nil) ve parametreler.
    struct Item {
        let mesh: MeshBuffers
        let texture: MTLTexture?
        var draw: Draw
    }

    let art: CharacterArt
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipe, shadowPipe: MTLRenderPipelineState
    let meshes: [String: MeshBuffers]
    private var textures: [String: MTLTexture] = [:]
    private let lock = NSLock()

    init(art: CharacterArt, device: MTLDevice, queue: MTLCommandQueue, library: MTLLibrary) throws {
        self.art = art
        self.device = device
        self.queue = queue
        let vertex = Self.vertexDescriptor()
        func pipe(_ vs: String, _ fs: String?, color: Bool, samples: Int) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vs)
            d.fragmentFunction = fs.flatMap { library.makeFunction(name: $0) }
            d.vertexDescriptor = vertex
            d.depthAttachmentPixelFormat = OfficeGPU.depthFormat
            d.rasterSampleCount = samples
            if color { d.colorAttachments[0].pixelFormat = OfficeGPU.colorFormat }
            return try device.makeRenderPipelineState(descriptor: d)
        }
        self.pipe = try pipe("charVS", "charFS", color: true, samples: OfficeGPU.sampleCount)
        shadowPipe = try pipe("charShadowVS", nil, color: false, samples: 1)
        var meshes: [String: MeshBuffers] = [:]
        for (name, m) in art.meshes {
            var data = Data(capacity: m.vertexCount * 40)
            for v in 0..<m.vertexCount {
                withUnsafeBytes(of: (m.positions[v * 3], m.positions[v * 3 + 1], m.positions[v * 3 + 2])) { data.append(contentsOf: $0) }
                withUnsafeBytes(of: (m.normals[v * 3], m.normals[v * 3 + 1], m.normals[v * 3 + 2])) { data.append(contentsOf: $0) }
                withUnsafeBytes(of: (m.uvs[v * 2], m.uvs[v * 2 + 1])) { data.append(contentsOf: $0) }
                data.append(contentsOf: m.joints[v * 4..<v * 4 + 4])
                data.append(contentsOf: m.weights[v * 4..<v * 4 + 4])
            }
            guard let vb = data.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }),
                  let ib = OfficeGPU.buffer(device, m.indices) else { throw OfficeGPU.Failure.resource("character mesh \(name)") }
            meshes[name] = MeshBuffers(vertices: vb, indices: ib, count: m.indices.count)
        }
        self.meshes = meshes
    }

    /// Konum, normal (float3), uv (float2), 4 kemik (uchar4), 4 ağırlık (uchar4, normalize): 40 bayt.
    static func vertexDescriptor() -> MTLVertexDescriptor {
        let d = MTLVertexDescriptor()
        let attributes: [(MTLVertexFormat, Int)] = [(.float3, 0), (.float3, 12), (.float2, 24), (.uchar4, 32), (.uchar4Normalized, 36)]
        for (i, (format, offset)) in attributes.enumerated() {
            d.attributes[i].format = format
            d.attributes[i].offset = offset
            d.attributes[i].bufferIndex = 0
        }
        d.layouts[0].stride = 40
        return d
    }

    static func checkLayout() { assert(MemoryLayout<Draw>.stride == 96) }

    /// Paket içi göreli yoldan doku (sRGB, mipmap'li, önceden çarpılmış alfa); önbellekli, thread-safe.
    func texture(_ relative: String) -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        if let t = textures[relative] { return t }
        guard let t = Self.loadTexture(art.directory.appendingPathComponent(relative), device: device, queue: queue) else {
            DebugLog.write("character texture missing: \(relative)")
            return nil
        }
        textures[relative] = t
        return t
    }

    static func loadTexture(_ url: URL, device: MTLDevice, queue: MTLCommandQueue) -> MTLTexture? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: w, height: h, mipmapped: true)
        d.usage = .shaderRead
        d.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: d) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: bytes, bytesPerRow: w * 4)
        if let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
        }
        return texture
    }

    static let modeCode: [CharacterArt.Mode: Float] = [.flat: 0, .albedo: 1, .tinted: 2, .pattern: 2, .eye: 3, .mouth: 3,
                                                       .decal: 3, .cutout: 4]

    /// Köylüler → çizim listesi (her parça bir çizim). `boneBase`: köylünün kemik paletindeki ilk indeks.
    func items(for avatars: [AvatarInstance], boneCount: Int, time: Double) -> [Item] {
        var out: [Item] = []
        for (i, a) in avatars.enumerated() {
            let look = a.look
            let selection = art.selection(for: look)
            var model = simd_float4x4(simd_quatf(angle: a.facing, axis: SIMD3(0, 1, 0)))
            model.columns.3 = SIMD4(a.position, 1)
            func rgb(_ c: AvatarLook.RGBA) -> SIMD3<Float> { SIMD3(Float(c.red), Float(c.green), Float(c.blue)) }
            let tints: [CharacterArt.Tint: SIMD3<Float>] = [
                .skin: rgb(AvatarLook.skinTones[look.skin % AvatarLook.skinTones.count]),
                .hair: rgb(AvatarLook.hairColors[look.hairColor % AvatarLook.hairColors.count]),
                .top: a.shirtColor,
                .bottom: rgb(AvatarLook.pantsColors[look.pantsColor % AvatarLook.pantsColors.count]),
                .shoes: rgb(AvatarLook.shoeColors[look.shoeColor % AvatarLook.shoeColors.count]),
            ]
            let face = AvatarExpression.face(clip: a.clip, waitReason: a.waitReason, restingMouth: AvatarExpression.resting(look.mouth),
                                             time: time, seed: StableHash.mixed(a.id))
            for part in art.parts(for: look) {
                guard let mesh = meshes[part.mesh] else { continue }
                var mode = part.mode
                // Allık kapalıysa yanaklar düz ten.
                if mode == .decal, !look.blush { mode = .flat }
                let path: String? = switch mode {
                case .eye: art.eyeTexture(style: selection.eyeStyle, expression: face.eye)
                case .mouth: art.mouthTexture(expression: face.mouth)
                case .pattern: part.texture ?? art.patterns[selection.pattern]
                case .flat: nil
                default: part.texture
                }
                let tint = part.tint.flatMap { tints[$0] } ?? part.color.map { SIMD3($0[0], $0[1], $0[2]) } ?? SIMD3(1, 1, 1)
                var texture: MTLTexture?
                if let path { texture = self.texture(path) }
                let code: Float = texture == nil ? 0 : (Self.modeCode[mode] ?? 0)
                let draw = Draw(model: model, tint: SIMD4(tint, code), boneBase: UInt32(i * boneCount))
                out.append(Item(mesh: mesh, texture: texture, draw: draw))
            }
        }
        return out
    }

    func encode(_ items: [Item], on e: MTLRenderCommandEncoder, shadow: Bool) {
        e.setRenderPipelineState(shadow ? shadowPipe : pipe)
        for var item in items {
            e.setVertexBuffer(item.mesh.vertices, offset: 0, index: 0)
            e.setVertexBytes(&item.draw, length: MemoryLayout<Draw>.stride, index: 2)
            if !shadow { e.setFragmentTexture(item.texture, index: 3) }
            e.drawIndexedPrimitives(type: .triangle, indexCount: item.mesh.count, indexType: .uint32, indexBuffer: item.mesh.indices,
                                    indexBufferOffset: 0)
        }
    }
}
