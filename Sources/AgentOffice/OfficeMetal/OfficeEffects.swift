import AgentOfficeCore
import CoreGraphics
import Metal
import simd

/// Baş üstü efektleri (`AvatarEffect`): kameraya dönük, saydam kartlar. Dokular burada CoreGraphics ile çizilir
/// (ter damlası, "!" çizgileri, parıltı, "z", nota); dışarıdan görsel yok.
final class OfficeEffects: @unchecked Sendable {
    struct Sprite {
        /// xyz: dünya (baş üstü noktası + yükseklik), w: boy (metre).
        var center: SIMD4<Float>
        /// x: ekranda sağa kayma (metre), y: katman, z: saydamlık.
        var params: SIMD4<Float>
    }

    static let size = 128
    let atlas: MTLTexture
    let pipe: MTLRenderPipelineState

    init(device: MTLDevice, queue: MTLCommandQueue, library: MTLLibrary) throws {
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "effectVS")
        d.fragmentFunction = library.makeFunction(name: "effectFS")
        d.colorAttachments[0].pixelFormat = OfficeGPU.colorFormat
        d.colorAttachments[0].isBlendingEnabled = true
        d.colorAttachments[0].sourceRGBBlendFactor = .one
        d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        d.colorAttachments[0].sourceAlphaBlendFactor = .one
        d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        d.depthAttachmentPixelFormat = OfficeGPU.depthFormat
        d.rasterSampleCount = OfficeGPU.sampleCount
        pipe = try device.makeRenderPipelineState(descriptor: d)
        atlas = try Self.makeAtlas(device: device, queue: queue)
    }

    /// Köylülerin efekt kartları. `pose`: köylünün skinning matrisleri; `head`: baş kemiği ve dinlenmedeki baş tepesi.
    static func sprites(for avatars: [AvatarInstance], time: Double, head: (bone: Int, top: SIMD3<Float>),
                        pose: (AvatarInstance) -> [simd_float4x4]) -> [Sprite] {
        var out: [Sprite] = []
        for a in avatars {
            guard let effect = AvatarEffect.current(clip: a.clip, waitReason: a.waitReason, clipTime: a.clipTime) else { continue }
            let m = pose(a)
            guard head.bone < m.count else { continue }
            var model = simd_float4x4(simd_quatf(angle: a.facing, axis: SIMD3(0, 1, 0)))
            model.columns.3 = SIMD4(a.position, 1)
            let top = simd_make_float3(model * m[head.bone] * SIMD4(head.top, 1))
            let phase = Double(StableHash.mixed(a.id) % 1000) / 1000
            for s in effect.sprites(time: time + phase) {
                out.append(Sprite(center: SIMD4(top + SIMD3(0, s.offset.y, 0), s.size),
                                  params: SIMD4(s.offset.x, Float(effect.rawValue), s.alpha, 0)))
            }
        }
        return out
    }

    // MARK: Dokular

    static func makeAtlas(device: MTLDevice, queue: MTLCommandQueue) throws -> MTLTexture {
        let n = size
        let d = MTLTextureDescriptor()
        d.textureType = .type2DArray
        d.pixelFormat = .rgba8Unorm_srgb
        d.width = n
        d.height = n
        d.arrayLength = AvatarEffect.allCases.count
        d.mipmapLevelCount = Int(log2(Double(n))) + 1
        d.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: d), let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw OfficeGPU.Failure.resource("effects")
        }
        for effect in AvatarEffect.allCases {
            var bytes = [UInt8](repeating: 0, count: n * n * 4)
            guard let ctx = CGContext(data: &bytes, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            draw(effect, in: ctx, size: CGFloat(n))
            texture.replace(region: MTLRegionMake2D(0, 0, n, n), mipmapLevel: 0, slice: effect.rawValue, withBytes: bytes,
                            bytesPerRow: n * 4, bytesPerImage: n * n * 4)
        }
        if let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
        }
        return texture
    }

    /// CoreGraphics'te y yukarı; dokuda satır 0 üst olduğu için çizim ters çevrilir.
    static func draw(_ effect: AvatarEffect, in c: CGContext, size s: CGFloat) {
        c.translateBy(x: 0, y: s)
        c.scaleBy(x: 1, y: -1)
        c.setLineCap(.round)
        c.setLineJoin(.round)
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
        let outline = rgb(1, 1, 1)
        switch effect {
        case .sweat:
            // Damla: üstte sivri, altta yuvarlak; açık mavi, beyaz kenar ve parlama.
            let p = CGMutablePath()
            p.move(to: CGPoint(x: s * 0.5, y: s * 0.10))
            p.addCurve(to: CGPoint(x: s * 0.5, y: s * 0.90), control1: CGPoint(x: s * 0.62, y: s * 0.40),
                       control2: CGPoint(x: s * 0.86, y: s * 0.90))
            p.addCurve(to: CGPoint(x: s * 0.5, y: s * 0.10), control1: CGPoint(x: s * 0.14, y: s * 0.90),
                       control2: CGPoint(x: s * 0.38, y: s * 0.40))
            c.addPath(p); c.setLineWidth(s * 0.09); c.setStrokeColor(outline); c.strokePath()
            c.addPath(p); c.setFillColor(rgb(0.45, 0.78, 1.0)); c.fillPath()
            c.setFillColor(rgb(1, 1, 1, 0.85))
            c.fillEllipse(in: CGRect(x: s * 0.40, y: s * 0.62, width: s * 0.10, height: s * 0.14))
        case .notice:
            // Üç kalın çizgi (sol, orta, sağ) yukarı doğru açılır.
            for (x0, x1, y0) in [(0.30, 0.16, 0.30), (0.50, 0.50, 0.20), (0.70, 0.84, 0.30)] as [(CGFloat, CGFloat, CGFloat)] {
                let a = CGPoint(x: s * x0, y: s * (1 - y0 - 0.18)), b = CGPoint(x: s * x1, y: s * (1 - y0 + 0.12))
                for (w, color) in [(s * 0.17, outline), (s * 0.10, rgb(1.0, 0.80, 0.15))] {
                    c.move(to: a); c.addLine(to: b); c.setLineWidth(w); c.setStrokeColor(color); c.strokePath()
                }
            }
        case .sparkle:
            // Dört köşeli yıldız: sarı, beyaz kenar.
            let p = CGMutablePath()
            let m = s / 2
            for i in 0..<8 {
                let r = i % 2 == 0 ? s * 0.44 : s * 0.12
                let a = CGFloat(i) * .pi / 4 + .pi / 2
                let pt = CGPoint(x: m + r * cos(a), y: m + r * sin(a))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            c.addPath(p); c.setLineWidth(s * 0.07); c.setStrokeColor(outline); c.strokePath()
            c.addPath(p); c.setFillColor(rgb(1.0, 0.86, 0.30)); c.fillPath()
        case .sleep:
            // "Z": üç kalın çizgi.
            let pts = [CGPoint(x: s * 0.26, y: s * 0.76), CGPoint(x: s * 0.74, y: s * 0.76), CGPoint(x: s * 0.26, y: s * 0.24),
                       CGPoint(x: s * 0.74, y: s * 0.24)]
            for (w, color) in [(s * 0.20, outline), (s * 0.11, rgb(0.42, 0.56, 0.98))] {
                c.move(to: pts[0]); for p in pts.dropFirst() { c.addLine(to: p) }
                c.setLineWidth(w); c.setStrokeColor(color); c.strokePath()
            }
        case .note:
            // Sekizlik nota: baş, sap ve bayrak.
            for (grow, color) in [(s * 0.05, outline), (0, rgb(0.95, 0.42, 0.62))] as [(CGFloat, CGColor)] {
                c.setFillColor(color); c.setStrokeColor(color)
                c.fillEllipse(in: CGRect(x: s * 0.22 - grow, y: s * 0.14 - grow, width: s * 0.30 + 2 * grow, height: s * 0.24 + 2 * grow))
                c.setLineWidth(s * 0.08 + 2 * grow)
                c.move(to: CGPoint(x: s * 0.49, y: s * 0.26)); c.addLine(to: CGPoint(x: s * 0.49, y: s * 0.84))
                c.addLine(to: CGPoint(x: s * 0.76, y: s * 0.66)); c.strokePath()
            }
        }
    }
}
