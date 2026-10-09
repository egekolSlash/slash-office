import AgentOfficeCore
import Foundation
import Metal
import simd

/// Uygulama başına bir kez kurulan Metal kaynakları (spec v4 §2): varlık dosyası, iskelet, shader'lar, desen dokusu
/// dizisi ve köylü mesh'i. Değişmez; birden çok çizici (mini ofis + ofis modu) paylaşır.
final class OfficeGPU: @unchecked Sendable {
    static let sampleCount = 4
    static let colorFormat = MTLPixelFormat.bgra8Unorm_srgb
    static let depthFormat = MTLPixelFormat.depth32Float

    let device: MTLDevice
    let queue: MTLCommandQueue
    let art: OfficeArtFile
    let skeleton: VillagerSkeleton
    let worldPipe, villagerPipe, ringPipe, skyPipe, worldShadowPipe, villagerShadowPipe: MTLRenderPipelineState
    let skyDepth: MTLDepthStencilState
    let depthWrite, depthTestOnly: MTLDepthStencilState
    let patterns: MTLTexture
    let patternSampler, shadowSampler: MTLSamplerState
    let villagerVertices, villagerIndices: MTLBuffer
    let villagerIndexCount: Int
    let ringVertices, ringIndices: MTLBuffer
    let ringIndexCount: Int

    private static let loading = Task.detached(priority: .userInitiated) { () -> OfficeGPU? in
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let dir = OfficeArtLocation.find(bundleResources: Bundle.main.resourceURL, repoRoot: repoRoot) else {
            DebugLog.write("office art not found; falling back to simple office")
            return nil
        }
        do {
            let art = try OfficeArtFile.load(from: dir.appendingPathComponent("office-art.json"))
            let gpu = try OfficeGPU(art: art)
            // JSON çözümünün geçici bellekleri sisteme geri verilsin.
            malloc_zone_pressure_relief(nil, 0)
            DebugLog.write("office metal resources loaded from \(dir.path)")
            return gpu
        } catch {
            DebugLog.write("office metal resources failed: \(error)")
            return nil
        }
    }

    /// Varlıklar ya da Metal yoksa nil: ofis sade görünüme düşer.
    static func shared() async -> OfficeGPU? { await loading.value }

    enum Failure: Error { case noDevice, resource(String) }

    init(art: OfficeArtFile) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw Failure.noDevice }
        self.device = device
        self.queue = queue
        self.art = art
        skeleton = VillagerSkeleton(art: art)
        let library = try device.makeLibrary(source: OfficeShaders.source, options: nil)
        let vertex = Self.vertexDescriptor()

        func pipe(_ vs: String, _ fs: String?, color: Bool, blend: Bool = false, samples: Int = OfficeGPU.sampleCount) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vs)
            d.fragmentFunction = fs.flatMap { library.makeFunction(name: $0) }
            d.vertexDescriptor = vertex
            d.depthAttachmentPixelFormat = Self.depthFormat
            d.rasterSampleCount = samples
            if color {
                d.colorAttachments[0].pixelFormat = Self.colorFormat
                if blend {
                    d.colorAttachments[0].isBlendingEnabled = true
                    d.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                    d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                    d.colorAttachments[0].sourceAlphaBlendFactor = .one
                    d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
                }
            }
            return try device.makeRenderPipelineState(descriptor: d)
        }
        worldPipe = try pipe("worldVS", "shadeFS", color: true)
        villagerPipe = try pipe("villagerVS", "shadeFS", color: true)
        ringPipe = try pipe("ringVS", "ringFS", color: true, blend: true)
        let sky = MTLRenderPipelineDescriptor()
        sky.vertexFunction = library.makeFunction(name: "skyVS")
        sky.fragmentFunction = library.makeFunction(name: "skyFS")
        sky.colorAttachments[0].pixelFormat = Self.colorFormat
        sky.depthAttachmentPixelFormat = Self.depthFormat
        sky.rasterSampleCount = Self.sampleCount
        skyPipe = try device.makeRenderPipelineState(descriptor: sky)
        let skyDepthDescriptor = MTLDepthStencilDescriptor()
        skyDepthDescriptor.depthCompareFunction = .always
        skyDepthDescriptor.isDepthWriteEnabled = false
        guard let skyDepth = device.makeDepthStencilState(descriptor: skyDepthDescriptor) else { throw Failure.resource("sky depth") }
        self.skyDepth = skyDepth
        worldShadowPipe = try pipe("worldShadowVS", nil, color: false, samples: 1)
        villagerShadowPipe = try pipe("villagerShadowVS", nil, color: false, samples: 1)

        let write = MTLDepthStencilDescriptor()
        write.depthCompareFunction = .lessEqual
        write.isDepthWriteEnabled = true
        let testOnly = MTLDepthStencilDescriptor()
        testOnly.depthCompareFunction = .lessEqual
        testOnly.isDepthWriteEnabled = false
        guard let depthWrite = device.makeDepthStencilState(descriptor: write),
              let depthTestOnly = device.makeDepthStencilState(descriptor: testOnly) else { throw Failure.resource("depth state") }
        self.depthWrite = depthWrite
        self.depthTestOnly = depthTestOnly

        patterns = try Self.makePatterns(device: device, queue: queue)
        let ps = MTLSamplerDescriptor()
        ps.sAddressMode = .repeat
        ps.tAddressMode = .repeat
        ps.minFilter = .linear
        ps.magFilter = .linear
        ps.mipFilter = .linear
        ps.maxAnisotropy = 4
        let ss = MTLSamplerDescriptor()
        ss.minFilter = .linear
        ss.magFilter = .linear
        ss.compareFunction = .lessEqual
        ss.sAddressMode = .clampToEdge
        ss.tAddressMode = .clampToEdge
        guard let patternSampler = device.makeSamplerState(descriptor: ps),
              let shadowSampler = device.makeSamplerState(descriptor: ss) else { throw Failure.resource("sampler") }
        self.patternSampler = patternSampler
        self.shadowSampler = shadowSampler

        var villager = OfficeMesh()
        villager.append(art.villager, at: .zero, skinned: true)
        guard let vv = Self.buffer(device, villager.vertices), let vi = Self.buffer(device, villager.indices) else {
            throw Failure.resource("villager mesh")
        }
        villagerVertices = vv
        villagerIndices = vi
        villagerIndexCount = villager.indices.count

        let ring = Self.ringMesh()
        guard let rv = Self.buffer(device, ring.vertices), let ri = Self.buffer(device, ring.indices) else { throw Failure.resource("ring") }
        ringVertices = rv
        ringIndices = ri
        ringIndexCount = ring.indices.count
    }

    /// `OfficeVertex` (40 bayt): paketli konum ve normal, UV, RGBA8, katman, kemik, parça.
    static func vertexDescriptor() -> MTLVertexDescriptor {
        let d = MTLVertexDescriptor()
        let attributes: [(MTLVertexFormat, Int)] = [(.float3, 0), (.float3, 12), (.float2, 24), (.uchar4Normalized, 32),
                                                    (.ushort, 36), (.uchar, 38), (.uchar, 39)]
        for (i, (format, offset)) in attributes.enumerated() {
            d.attributes[i].format = format
            d.attributes[i].offset = offset
            d.attributes[i].bufferIndex = 0
        }
        d.layouts[0].stride = MemoryLayout<OfficeVertex>.stride
        return d
    }

    static func buffer<T>(_ device: MTLDevice, _ array: [T]) -> MTLBuffer? {
        guard !array.isEmpty else { return nil }
        return array.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    }

    /// Desen dokusu dizisi (sRGB, mipmap'li): katman `i` = `OfficePatterns.image(layer: i)`.
    static func makePatterns(device: MTLDevice, queue: MTLCommandQueue) throws -> MTLTexture {
        let s = OfficePatterns.size
        let d = MTLTextureDescriptor()
        d.textureType = .type2DArray
        d.pixelFormat = .rgba8Unorm_srgb
        d.width = s
        d.height = s
        d.arrayLength = OfficeTextureLayer.count
        d.mipmapLevelCount = Int(log2(Double(s))) + 1
        d.usage = .shaderRead
        d.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: d) else { throw Failure.resource("patterns") }
        for layer in 0..<OfficeTextureLayer.count {
            let image = OfficePatterns.image(layer: layer)
            guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { throw Failure.resource("pattern \(layer)") }
            texture.replace(region: MTLRegionMake2D(0, 0, s, s), mipmapLevel: 0, slice: layer, withBytes: bytes,
                            bytesPerRow: image.bytesPerRow, bytesPerImage: image.bytesPerRow * s)
        }
        guard let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() else { throw Failure.resource("mipmaps") }
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        return texture
    }

    /// Bekleme halkası: düz disk (yarıçap 0,32), halının (üstü 0,012) hemen üstünde.
    static func ringMesh() -> OfficeMesh {
        var mesh = OfficeMesh()
        let segments = 40
        let up = SIMD3<Float>(0, 1, 0)
        mesh.vertices.append(OfficeVertex(position: SIMD3(0, 0.02, 0), normal: up, uv: .zero, color: SIMD4(255, 255, 255, 0)))
        for i in 0...segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            mesh.vertices.append(OfficeVertex(position: SIMD3(0.32 * cos(a), 0.02, 0.32 * sin(a)), normal: up, uv: .zero,
                                              color: SIMD4(255, 255, 255, 0)))
        }
        for i in 1...UInt32(segments) { mesh.indices += [0, i + 1, i] }
        return mesh
    }
}

/// Bir ofis görünümünün çizicisi (spec v4 §2–3): sadece çizim thread'inde kullanılır.
/// Kare başına 4 draw call: köylü gölgesi, statik dünya, köylüler, halkalar (+ dünya değişince bir kez statik gölge).
final class OfficeMetalRenderer: @unchecked Sendable {
    struct Uniforms {
        var viewProj: simd_float4x4
        var lightViewProj: simd_float4x4
        var lightDir: SIMD4<Float>
        var sun: SIMD4<Float>
        var sky: SIMD4<Float>
        var ground: SIMD4<Float>
        var params: SIMD4<Float>
        /// x: bükülmenin başladığı z, y: katsayı (`OfficeViewport.bend`).
        var bend: SIMD4<Float>
        var skyTop: SIMD4<Float>
        var skyHorizon: SIMD4<Float>
        /// x: emissive çarpanı, y: yıldızlar, z: oda içi sıcak ışık (0…1).
        var light: SIMD4<Float>
    }

    struct VillagerData {
        var model: simd_float4x4
        var shirt: SIMD4<Float>
        var skin: SIMD4<Float>
        var hair: SIMD4<Float>
        var pants: SIMD4<Float>
        var shoes: SIMD4<Float>
        /// 16 bayt: `VillagerVariant` grubu → seçili değer (bayt g).
        var variants: SIMD4<UInt32>
        var boneBase: UInt32
        var pad: (UInt32, UInt32, UInt32) = (0, 0, 0)
    }

    /// 16 varyant baytı → 4 kelime (küçük uçlu: bayt g, kelime g/4'ün (g%4)·8. biti).
    static func packVariants(_ bytes: [UInt8]) -> SIMD4<UInt32> {
        var words = SIMD4<UInt32>(repeating: 0)
        for (g, value) in bytes.prefix(16).enumerated() { words[g / 4] |= UInt32(value) << UInt32((g % 4) * 8) }
        return words
    }

    static func checkLayouts() {
        // MSL yapılarıyla aynı boyut (shader'daki VillagerData 176, Uniforms 272 bayt).
        assert(MemoryLayout<VillagerData>.stride == 176 && MemoryLayout<Uniforms>.stride == 272)
    }

    /// Saatin ışığı (gece/gündüz döngüsü); varsayılan öğlen.
    private(set) var lighting = OfficeDaylight.at(hour: 13)

    static let staticShadowSize = 2048
    static let villagerShadowSize = 1024
    static let framesInFlight = 3
    static func linear(_ c: SIMD3<Double>) -> SIMD3<Float> {
        func f(_ x: Double) -> Float { Float(x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)) }
        return SIMD3(f(c.x), f(c.y), f(c.z))
    }

    let gpu: OfficeGPU
    private var worldVertices: MTLBuffer?
    private var worldIndices: MTLBuffer?
    private var worldIndexCount = 0
    private var islandBounds = PlanRect.zero
    private var lightViewProj = matrix_identity_float4x4
    private var shadowDirection = SIMD3<Double>(0, -1, 0)
    private var staticShadowDirty = false
    private let staticShadow: MTLTexture
    private let villagerShadow: MTLTexture
    private var colorMSAA: MTLTexture?
    private var depthMSAA: MTLTexture?
    private var villagerBuffers: [MTLBuffer?]
    private var boneBuffers: [MTLBuffer?]
    private var ringBuffers: [MTLBuffer?]
    private var frame = 0
    private let inFlight = DispatchSemaphore(value: OfficeMetalRenderer.framesInFlight)

    init(gpu: OfficeGPU) throws {
        self.gpu = gpu
        Self.checkLayouts()
        func shadowMap(_ size: Int) throws -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: OfficeGPU.depthFormat, width: size, height: size, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            guard let t = gpu.device.makeTexture(descriptor: d) else { throw OfficeGPU.Failure.resource("shadow map") }
            return t
        }
        staticShadow = try shadowMap(Self.staticShadowSize)
        villagerShadow = try shadowMap(Self.villagerShadowSize)
        villagerBuffers = Array(repeating: nil, count: Self.framesInFlight)
        boneBuffers = Array(repeating: nil, count: Self.framesInFlight)
        ringBuffers = Array(repeating: nil, count: Self.framesInFlight)
    }

    /// Yeni statik dünya: tamponlar burada (çizim thread'inde) değişir, yani kare ortasında yarım dünya çizilmez.
    /// Uçuştaki komut tamponları eski tamponları kendileri tutar.
    func setWorld(_ mesh: OfficeMesh, site: PlanRect) {
        worldVertices = OfficeGPU.buffer(gpu.device, mesh.vertices)
        worldIndices = OfficeGPU.buffer(gpu.device, mesh.indices)
        worldIndexCount = worldVertices == nil ? 0 : mesh.indices.count
        // Gölge haritası odaları, arsaları ve meydanı (+2 m) kaplar; çayırın gerisi gölgesizdir.
        let margin = 2.0
        islandBounds = PlanRect(minX: site.minX - margin, minZ: site.minZ - margin, maxX: site.maxX + margin, maxZ: site.maxZ + margin)
        updateLightProjection()
    }

    /// Yeni ışık: güneşin yönü yarım dereceden fazla değiştiyse statik gölge haritası yeniden çizilir.
    func setLighting(_ lighting: OfficeDaylight.Lighting) {
        self.lighting = lighting
        if simd_dot(lighting.direction, shadowDirection) < cos(0.5 * .pi / 180) { updateLightProjection() }
    }

    private func updateLightProjection() {
        shadowDirection = lighting.direction
        lightViewProj = OfficeViewport.lightViewProjection(bounds: islandBounds, height: 3.2, direction: shadowDirection)
        staticShadowDirty = true
    }

    var hasWorld: Bool { worldIndexCount > 0 }

    /// Bir kare: `target`'a (drawable ya da ekran dışı doku) çizer. En fazla `framesInFlight` kare uçuşta olur;
    /// gerekirse burada GPU'yu bekler.
    func encode(to target: MTLTexture, viewport: OfficeViewport, viewSize: OfficeViewport.ViewSize, avatars: [AvatarInstance],
                time: Double, commandBuffer cb: MTLCommandBuffer) {
        inFlight.wait()
        let semaphore = inFlight
        cb.addCompletedHandler { _ in semaphore.signal() }
        frame = (frame + 1) % Self.framesInFlight
        ensureTargets(width: target.width, height: target.height)

        var u = Uniforms(viewProj: viewport.viewProjection(viewSize: viewSize), lightViewProj: lightViewProj,
                         lightDir: SIMD4(SIMD3<Float>(shadowDirection), 0),
                         sun: SIMD4(SIMD3<Float>(lighting.sun), 0), sky: SIMD4(SIMD3<Float>(lighting.skyAmbient), 0),
                         ground: SIMD4(SIMD3<Float>(lighting.groundAmbient), 0),
                         params: SIMD4(Float(time), avatars.isEmpty ? 0 : 1, 1 / Float(Self.staticShadowSize), 1 / Float(Self.villagerShadowSize)),
                         bend: SIMD4(Float(viewport.bend.startZ), Float(viewport.bend.k), 0, 0),
                         skyTop: SIMD4(Self.linear(lighting.sky * 0.86), 0),
                         skyHorizon: SIMD4(Self.linear(lighting.sky + (SIMD3(1, 1, 1) - lighting.sky) * 0.3), 0),
                         light: SIMD4(Float(lighting.emissive), Float(lighting.stars), Float(lighting.interior), 0))
        let villagerCount = writeVillagers(avatars)
        let ringCount = writeRings(avatars, time: time)

        if staticShadowDirty, let vb = worldVertices, let ib = worldIndices {
            staticShadowDirty = false
            shadowPass(cb, staticShadow) { e in
                e.setRenderPipelineState(gpu.worldShadowPipe)
                e.setVertexBuffer(vb, offset: 0, index: 0)
                e.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                e.drawIndexedPrimitives(type: .triangle, indexCount: worldIndexCount, indexType: .uint32, indexBuffer: ib, indexBufferOffset: 0)
            }
        }
        if villagerCount > 0 {
            shadowPass(cb, villagerShadow) { e in
                e.setRenderPipelineState(gpu.villagerShadowPipe)
                bindVillagers(e, &u)
                e.drawIndexedPrimitives(type: .triangle, indexCount: gpu.villagerIndexCount, indexType: .uint32,
                                        indexBuffer: gpu.villagerIndices, indexBufferOffset: 0, instanceCount: villagerCount)
            }
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = colorMSAA
        pass.colorAttachments[0].resolveTexture = target
        pass.colorAttachments[0].loadAction = .clear
        let skyLinear = Self.linear(lighting.sky)
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(skyLinear.x), green: Double(skyLinear.y),
                                                            blue: Double(skyLinear.z), alpha: 1)
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.depthAttachment.texture = depthMSAA
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let e = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        e.label = "office"
        e.setDepthStencilState(gpu.depthWrite)
        e.setCullMode(.back)
        e.setFrontFacing(.counterClockwise)
        e.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        e.setFragmentTexture(gpu.patterns, index: 0)
        e.setFragmentTexture(staticShadow, index: 1)
        e.setFragmentTexture(villagerShadow, index: 2)
        e.setFragmentSamplerState(gpu.patternSampler, index: 0)
        e.setFragmentSamplerState(gpu.shadowSampler, index: 1)
        // Gökyüzü (geçiş ve yıldızlar) en arkada.
        e.setRenderPipelineState(gpu.skyPipe)
        e.setDepthStencilState(gpu.skyDepth)
        e.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        e.setDepthStencilState(gpu.depthWrite)
        if let vb = worldVertices, let ib = worldIndices {
            e.setRenderPipelineState(gpu.worldPipe)
            e.setVertexBuffer(vb, offset: 0, index: 0)
            e.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            e.drawIndexedPrimitives(type: .triangle, indexCount: worldIndexCount, indexType: .uint32, indexBuffer: ib, indexBufferOffset: 0)
        }
        if villagerCount > 0 {
            e.setRenderPipelineState(gpu.villagerPipe)
            bindVillagers(e, &u)
            e.drawIndexedPrimitives(type: .triangle, indexCount: gpu.villagerIndexCount, indexType: .uint32,
                                    indexBuffer: gpu.villagerIndices, indexBufferOffset: 0, instanceCount: villagerCount)
        }
        if ringCount > 0, let rings = ringBuffers[frame] {
            e.setRenderPipelineState(gpu.ringPipe)
            e.setDepthStencilState(gpu.depthTestOnly)
            e.setCullMode(.none)
            e.setVertexBuffer(gpu.ringVertices, offset: 0, index: 0)
            e.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            e.setVertexBuffer(rings, offset: 0, index: 2)
            e.drawIndexedPrimitives(type: .triangle, indexCount: gpu.ringIndexCount, indexType: .uint32,
                                    indexBuffer: gpu.ringIndices, indexBufferOffset: 0, instanceCount: ringCount)
        }
        e.endEncoding()
    }

    private func bindVillagers(_ e: MTLRenderCommandEncoder, _ u: inout Uniforms) {
        e.setVertexBuffer(gpu.villagerVertices, offset: 0, index: 0)
        e.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        e.setVertexBuffer(villagerBuffers[frame], offset: 0, index: 2)
        e.setVertexBuffer(boneBuffers[frame], offset: 0, index: 3)
    }

    private func shadowPass(_ cb: MTLCommandBuffer, _ map: MTLTexture, draw: (MTLRenderCommandEncoder) -> Void) {
        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = map
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .store
        guard let e = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        e.label = "shadow"
        e.setDepthStencilState(gpu.depthWrite)
        e.setCullMode(.none)
        e.setDepthBias(1, slopeScale: 2, clamp: 0.01)
        draw(e)
        e.endEncoding()
    }

    /// Köylü instance'ları ve kemik matrisleri bu karenin halka tamponuna.
    private func writeVillagers(_ avatars: [AvatarInstance]) -> Int {
        guard !avatars.isEmpty else { return 0 }
        let bones = gpu.skeleton.boneCount
        let villagers = Self.ensure(&villagerBuffers[frame], gpu.device, avatars.count * MemoryLayout<VillagerData>.stride)
        let boneBuffer = Self.ensure(&boneBuffers[frame], gpu.device, max(1, avatars.count * bones) * MemoryLayout<simd_float4x4>.stride)
        let vp = villagers.contents().bindMemory(to: VillagerData.self, capacity: avatars.count)
        let bp = boneBuffer.contents().bindMemory(to: simd_float4x4.self, capacity: max(1, avatars.count * bones))
        for (i, a) in avatars.enumerated() {
            var model = simd_float4x4(simd_quatf(angle: a.facing, axis: SIMD3(0, 1, 0)))
            model.columns.3 = SIMD4(a.position, 1)
            let skin = AvatarLook.skinTones[a.look.skin % AvatarLook.skinTones.count]
            let hair = AvatarLook.hairColors[a.look.hairColor % AvatarLook.hairColors.count]
            let pants = AvatarLook.pantsColors[a.look.pantsColor % AvatarLook.pantsColors.count]
            let shoes = AvatarLook.shoeColors[a.look.shoeColor % AvatarLook.shoeColors.count]
            vp[i] = VillagerData(model: model,
                                 shirt: SIMD4(a.shirtColor, Float(OfficeTextureLayer.shirt(a.look.shirtPattern))),
                                 skin: SIMD4(Float(skin.red), Float(skin.green), Float(skin.blue), 0),
                                 hair: SIMD4(Float(hair.red), Float(hair.green), Float(hair.blue), 0),
                                 pants: SIMD4(Float(pants.red), Float(pants.green), Float(pants.blue), 0),
                                 shoes: SIMD4(Float(shoes.red), Float(shoes.green), Float(shoes.blue), 0),
                                 variants: Self.packVariants(a.look.variantValues),
                                 boneBase: UInt32(i * bones))
            let pose = gpu.skeleton.pose(of: a)
            for b in 0..<bones { bp[i * bones + b] = b < pose.count ? pose[b] : matrix_identity_float4x4 }
        }
        return avatars.count
    }

    /// Bekleyen (el sallayan) köylülerin ayağının altında nabız gibi atan halka.
    private func writeRings(_ avatars: [AvatarInstance], time: Double) -> Int {
        let waving = avatars.filter(\.waving)
        guard !waving.isEmpty else { return 0 }
        let buffer = Self.ensure(&ringBuffers[frame], gpu.device, waving.count * MemoryLayout<SIMD4<Float>>.stride)
        let p = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: waving.count)
        let pulse = Float(1 + 0.18 * sin(time * 5))
        for (i, a) in waving.enumerated() { p[i] = SIMD4(a.position, pulse) }
        return waving.count
    }

    private static func ensure(_ buffer: inout MTLBuffer?, _ device: MTLDevice, _ length: Int) -> MTLBuffer {
        if let b = buffer, b.length >= length { return b }
        let b = device.makeBuffer(length: max(length * 2, 256), options: .storageModeShared)!
        buffer = b
        return b
    }

    private func ensureTargets(width: Int, height: Int) {
        if let c = colorMSAA, c.width == width, c.height == height { return }
        func make(_ format: MTLPixelFormat) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            d.textureType = .type2DMultisample
            d.sampleCount = OfficeGPU.sampleCount
            d.usage = .renderTarget
            // Apple GPU'larında MSAA hedefleri bellekte yer tutmaz; diğerlerinde (Intel/AMD) özel bellek.
            d.storageMode = gpu.device.supportsFamily(.apple1) ? .memoryless : .private
            return gpu.device.makeTexture(descriptor: d)
        }
        colorMSAA = make(OfficeGPU.colorFormat)
        depthMSAA = make(OfficeGPU.depthFormat)
    }
}
