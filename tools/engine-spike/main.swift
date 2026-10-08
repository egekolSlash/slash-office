// Ofis motoru denemesi (docs/notes/spike-office-engines.md). Uygulamanın parçası değil.
// Yüzen (tüm Space'lerde görünen) pencerede çalışır; her 2 sn'de fps, kare başına CPU ve süreç CPU'sunu yazar.
//   tools/engine-spike/build.sh
//   tools/engine-spike/.build/EngineSpike metal native 0     (native = ekran yenileme hızı; 0 = kapatana kadar)
//   tools/engine-spike/.build/EngineSpike metal 24 60        (24 fps, 60 sn)
//   tools/engine-spike/.build/EngineSpike laya 24 0          (WKWebView + LayaAir; WebKit süreçlerini Activity Monitor'den ekleyin)
import AppKit
import Metal
import MetalKit
import ModelIO
import QuartzCore
import WebKit
import simd

let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "metal"
let native = args.count > 2 && args[2] == "native"
let fps = native ? 120 : (Double(args.count > 2 ? args[2] : "24") ?? 24)
let duration = Double(args.count > 3 ? args[3] : "20") ?? 20
setvbuf(stdout, nil, _IONBF, 0)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1200, height: 800), styleMask: [.titled, .closable, .resizable],
                      backing: .buffered, defer: false)
window.title = "Motor ölçümü: \(mode) \(native ? "native" : "\(Int(fps))") fps" + (duration > 0 ? " (\(Int(duration)) sn)" : " (kapatınca biter)")
window.level = .floating
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
final class Closer: NSObject, NSWindowDelegate { func windowWillClose(_ n: Notification) { exit(0) } }
let closer = Closer()
window.delegate = closer
var keep: [AnyObject] = []

/// Sürecin toplam CPU süresi (kullanıcı + sistem, sn).
func processCPU() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
}

// MARK: - LayaAir

final class Logger: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { print("[js]", m.body) }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { print("[nav] fail", e) }
    func webViewWebContentProcessDidTerminate(_ w: WKWebView) { print("[nav] web content terminated") }
}

func startLaya() {
    let config = WKWebViewConfiguration()
    let logger = Logger()
    keep.append(logger)
    config.userContentController.add(logger, name: "log")
    let web = WKWebView(frame: window.contentView!.bounds, configuration: config)
    web.autoresizingMask = [.width, .height]
    web.navigationDelegate = logger
    window.contentView!.addSubview(web)
    let dir = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("laya")
    var comps = URLComponents(url: dir.appendingPathComponent("index.html"), resolvingAgainstBaseURL: false)!
    comps.queryItems = [URLQueryItem(name: "fps", value: String(Int(native ? 120 : fps)))]
    web.loadFileURL(comps.url!, allowingReadAccessTo: dir)
    keep.append(web)
}

// MARK: - Metal

struct Instance { var model: simd_float4x4; var color: SIMD4<Float> }
struct Uniforms { var viewProj: simd_float4x4; var lightViewProj: simd_float4x4; var lightDir: SIMD4<Float> }

let shaderSource = """
#include <metal_stdlib>
using namespace metal;
struct VIn { float3 pos [[attribute(0)]]; float3 nrm [[attribute(1)]]; };
struct Instance { float4x4 model; float4 color; };
struct Uniforms { float4x4 viewProj; float4x4 lightViewProj; float4 lightDir; };
struct VOut { float4 pos [[position]]; float3 nrm; float4 color; float4 lpos; };
vertex float4 shadowVS(VIn v [[stage_in]], constant Instance *inst [[buffer(1)]], constant Uniforms &u [[buffer(2)]], uint iid [[instance_id]]) {
    return u.lightViewProj * inst[iid].model * float4(v.pos, 1);
}
vertex VOut mainVS(VIn v [[stage_in]], constant Instance *inst [[buffer(1)]], constant Uniforms &u [[buffer(2)]], uint iid [[instance_id]]) {
    VOut o; float4 w = inst[iid].model * float4(v.pos, 1);
    o.pos = u.viewProj * w; o.nrm = normalize((inst[iid].model * float4(v.nrm, 0)).xyz);
    o.color = inst[iid].color; o.lpos = u.lightViewProj * w; return o;
}
fragment float4 mainFS(VOut i [[stage_in]], constant Uniforms &u [[buffer(2)]], depth2d<float> sm [[texture(0)]]) {
    constexpr sampler s(coord::normalized, filter::linear, compare_func::less_equal);
    float3 p = i.lpos.xyz / i.lpos.w; float2 uv = p.xy * float2(0.5, -0.5) + 0.5;
    float lit = 0; for (int x = -1; x <= 1; x++) for (int y = -1; y <= 1; y++)
        lit += sm.sample_compare(s, uv + float2(x, y) / 2048.0, p.z - 0.002);
    lit /= 9.0;
    float diff = max(dot(i.nrm, -u.lightDir.xyz), 0.0);
    return float4(i.color.rgb * (0.55 + 0.6 * diff * lit), 1);
}
"""

final class MetalSpike {
    let device = MTLCreateSystemDefaultDevice()!
    let layer = CAMetalLayer()
    var queue: MTLCommandQueue!
    var mainPipe: MTLRenderPipelineState!, shadowPipe: MTLRenderPipelineState!
    var depthState: MTLDepthStencilState!
    var meshes: [MTKMesh] = []
    var instances: [[Instance]] = [[], []]
    var parts: [(mesh: Int, index: Int, base: simd_float4x4)] = []
    var shadowMap: MTLTexture!, depth: MTLTexture?
    var ring: [[MTLBuffer]] = []
    var frameIndex = 0
    let inFlight = DispatchSemaphore(value: 3)

    init(view: NSView) throws {
        layer.device = device; layer.pixelFormat = .bgra8Unorm_srgb; layer.framebufferOnly = true
        layer.displaySyncEnabled = true; layer.maximumDrawableCount = 3
        layer.contentsScale = window.backingScaleFactor
        layer.drawableSize = CGSize(width: 1200 * layer.contentsScale, height: 800 * layer.contentsScale)
        view.wantsLayer = true; view.layer = layer
        queue = device.makeCommandQueue()
        let lib = try device.makeLibrary(source: shaderSource, options: nil)
        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float3; vd.attributes[0].offset = 0
        vd.attributes[1].format = .float3; vd.attributes[1].offset = 12
        vd.layouts[0].stride = 24
        let mdlVD = MTKModelIOVertexDescriptorFromMetal(vd)
        (mdlVD.attributes[0] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        (mdlVD.attributes[1] as! MDLVertexAttribute).name = MDLVertexAttributeNormal
        let alloc = MTKMeshBufferAllocator(device: device)
        let boxM = MDLMesh(boxWithExtent: [1, 1, 1], segments: [1, 1, 1], inwardNormals: false, geometryType: .triangles, allocator: alloc)
        let sphM = MDLMesh(sphereWithExtent: [1, 1, 1], segments: [16, 16], inwardNormals: false, geometryType: .triangles, allocator: alloc)
        for m in [boxM, sphM] { m.vertexDescriptor = mdlVD; meshes.append(try MTKMesh(mesh: m, device: device)) }
        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = lib.makeFunction(name: "mainVS"); pd.fragmentFunction = lib.makeFunction(name: "mainFS")
        pd.vertexDescriptor = vd; pd.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb; pd.depthAttachmentPixelFormat = .depth32Float
        mainPipe = try device.makeRenderPipelineState(descriptor: pd)
        let sd = MTLRenderPipelineDescriptor()
        sd.vertexFunction = lib.makeFunction(name: "shadowVS"); sd.vertexDescriptor = vd; sd.depthAttachmentPixelFormat = .depth32Float
        shadowPipe = try device.makeRenderPipelineState(descriptor: sd)
        let ds = MTLDepthStencilDescriptor(); ds.depthCompareFunction = .less; ds.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: ds)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 2048, height: 2048, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .private
        shadowMap = device.makeTexture(descriptor: td)
        // Sahne: 500 statik parça + 6 karakter × 11 hareketli parça.
        var seed: UInt64 = 7
        func rnd() -> Float { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Float(seed >> 40) / Float(1 << 24) }
        func color(_ i: Int) -> SIMD4<Float> { [0.4 + Float(i * 37 % 60) / 100, 0.4 + Float(i * 53 % 60) / 100, 0.3 + Float(i * 71 % 60) / 100, 1] }
        for i in 0..<500 {
            let m = translate(rnd() * 10 - 2, rnd() * 1.2, rnd() * 9 - 2) * scale(0.2 + rnd() * 0.6, 0.1 + rnd() * 0.8, 0.2 + rnd() * 0.6)
            instances[i % 3 == 0 ? 1 : 0].append(Instance(model: m, color: color(i % 12)))
        }
        for c in 0..<6 {
            for p in 0..<11 {
                let k = p % 2
                let base = translate(Float(c) * 1.2 + sin(Float(p)) * 0.2, 0.1 + Float(p) * 0.08, 4 + cos(Float(p)) * 0.2) * scale(0.18, 0.18, 0.18)
                parts.append((k, instances[k].count, base))
                instances[k].append(Instance(model: base, color: color(c + p)))
            }
        }
        ring = (0..<2).map { k in (0..<3).map { _ in device.makeBuffer(length: instances[k].count * MemoryLayout<Instance>.stride, options: .storageModeShared)! } }
    }

    func start() {
        let thread = Thread { [self] in
            let begin = CACurrentMediaTime()
            var last = begin, windowStart = begin, windowFrames = 0, windowCPU = 0.0
            var cpuStart = processCPU()
            var t: Float = 0
            while duration <= 0 || CACurrentMediaTime() - begin < duration {
                let f0 = CACurrentMediaTime()
                t += Float(f0 - last); last = f0
                // native: nextDrawable() vsync'e kadar bekler (bekleme CPU harcamaz); kare hızını ekran belirler.
                let work = autoreleasepool { frame(t) }
                windowFrames += 1; windowCPU += work
                if !native {
                    let wait = 1 / fps - (CACurrentMediaTime() - f0)
                    if wait > 0 { Thread.sleep(forTimeInterval: wait) }
                }
                let now = CACurrentMediaTime()
                if now - windowStart >= 2 {
                    let cpuNow = processCPU()
                    print(String(format: "fps=%.1f  kare başına CPU=%.3f ms  süreç CPU=%%%.1f",
                                 Double(windowFrames) / (now - windowStart), windowCPU / Double(windowFrames) * 1000,
                                 (cpuNow - cpuStart) / (now - windowStart) * 100))
                    windowStart = now; windowFrames = 0; windowCPU = 0; cpuStart = cpuNow
                }
            }
            exit(0)
        }
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Kare hazırlama + kodlama süresi (sn); drawable beklemesi hariç.
    func frame(_ t: Float) -> Double {
        let begin = CACurrentMediaTime()
        for (i, part) in parts.enumerated() {
            instances[part.mesh][part.index].model = part.base * rotateX(sin(t * 6 + Float(i)) * 0.5)
        }
        inFlight.wait()
        frameIndex = (frameIndex + 1) % 3
        for k in 0..<2 { instances[k].withUnsafeBytes { ring[k][frameIndex].contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) } }
        var work = CACurrentMediaTime() - begin
        guard let drawable = layer.nextDrawable(), let cb = queue.makeCommandBuffer() else { inFlight.signal(); return work }
        let encodeStart = CACurrentMediaTime()
        cb.addCompletedHandler { [inFlight] _ in inFlight.signal() }
        if depth == nil || depth!.width != drawable.texture.width {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: drawable.texture.width, height: drawable.texture.height, mipmapped: false)
            d.usage = .renderTarget; d.storageMode = .private; depth = device.makeTexture(descriptor: d)
        }
        let target = SIMD3<Float>(3, 0, 3)
        let view = lookAt(eye: target + SIMD3<Float>(18, 18, 18), center: target, up: [0, 1, 0])
        let viewProj = ortho(halfW: 9, halfH: 6, near: 0.1, far: 100) * view
        let lightDir = simd_normalize(SIMD3<Float>(-0.5, -1, -0.4))
        let lightVP = ortho(halfW: 10, halfH: 10, near: 0.1, far: 50) * lookAt(eye: target - lightDir * 20, center: target, up: [0, 1, 0])
        var u = Uniforms(viewProj: viewProj, lightViewProj: lightVP, lightDir: SIMD4<Float>(lightDir, 0))
        let sp = MTLRenderPassDescriptor()
        sp.depthAttachment.texture = shadowMap; sp.depthAttachment.loadAction = .clear; sp.depthAttachment.clearDepth = 1; sp.depthAttachment.storeAction = .store
        let se = cb.makeRenderCommandEncoder(descriptor: sp)!
        se.setRenderPipelineState(shadowPipe); se.setDepthStencilState(depthState)
        draw(se, &u)
        se.endEncoding()
        let mp = MTLRenderPassDescriptor()
        mp.colorAttachments[0].texture = drawable.texture; mp.colorAttachments[0].loadAction = .clear
        mp.colorAttachments[0].clearColor = MTLClearColor(red: 0.62, green: 0.82, blue: 1, alpha: 1); mp.colorAttachments[0].storeAction = .store
        mp.depthAttachment.texture = depth; mp.depthAttachment.loadAction = .clear; mp.depthAttachment.clearDepth = 1
        let me = cb.makeRenderCommandEncoder(descriptor: mp)!
        me.setRenderPipelineState(mainPipe); me.setDepthStencilState(depthState); me.setFragmentTexture(shadowMap, index: 0)
        me.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 2)
        draw(me, &u)
        me.endEncoding()
        cb.present(drawable)
        cb.commit()
        work += CACurrentMediaTime() - encodeStart
        return work
    }

    /// Mesh tipi başına bir örneklemeli çizim: geçiş başına 2, kare başına 4 draw call.
    func draw(_ e: MTLRenderCommandEncoder, _ u: inout Uniforms) {
        e.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 2)
        for (k, mesh) in meshes.enumerated() {
            e.setVertexBuffer(ring[k][frameIndex], offset: 0, index: 1)
            e.setVertexBuffer(mesh.vertexBuffers[0].buffer, offset: mesh.vertexBuffers[0].offset, index: 0)
            for sub in mesh.submeshes {
                e.drawIndexedPrimitives(type: sub.primitiveType, indexCount: sub.indexCount, indexType: sub.indexType,
                                        indexBuffer: sub.indexBuffer.buffer, indexBufferOffset: sub.indexBuffer.offset,
                                        instanceCount: instances[k].count)
            }
        }
    }
}

func translate(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 { var m = matrix_identity_float4x4; m.columns.3 = [x, y, z, 1]; return m }
func scale(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 { simd_float4x4(diagonal: [x, y, z, 1]) }
func rotateX(_ a: Float) -> simd_float4x4 { simd_float4x4([1, 0, 0, 0], [0, cos(a), sin(a), 0], [0, -sin(a), cos(a), 0], [0, 0, 0, 1]) }
func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
    let f = simd_normalize(center - eye), s = simd_normalize(simd_cross(f, up)), u = simd_cross(s, f)
    return simd_float4x4([s.x, u.x, -f.x, 0], [s.y, u.y, -f.y, 0], [s.z, u.z, -f.z, 0], [-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1])
}
func ortho(halfW: Float, halfH: Float, near: Float, far: Float) -> simd_float4x4 {
    simd_float4x4([1 / halfW, 0, 0, 0], [0, 1 / halfH, 0, 0], [0, 0, -1 / (far - near), 0], [0, 0, -near / (far - near), 1])
}

if mode == "laya" {
    startLaya()
    if duration > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + duration) { exit(0) } }
} else {
    do {
        let spike = try MetalSpike(view: window.contentView!)
        keep.append(spike)
        spike.start()
    } catch { print("metal error:", error); exit(1) }
}
window.orderFrontRegardless()
app.run()
