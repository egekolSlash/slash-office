import AgentOfficeCore
import AppKit
import Metal

/// `AgentOffice --office-snapshot <png> [--zoom <z>] [--live] [--focus-waiting]`: demo ofisini ekran dışı çizip PNG yazar ve çıkar.
/// Masa çapalarına (kartların asıldığı nokta) kırmızı nokta basılır: 3D sahne ile SwiftUI katmanının hizasını
/// gözle kontrol etmek için. `--live`: köylüler kapıdan yürüyerek gelir (1,5 sn sonraki an).
@MainActor
enum OfficeSnapshot {
    static func requested(_ arguments: [String]) -> Bool { arguments.contains("--office-snapshot") }

    static func run(arguments: [String], model: AppModel) async {
        setvbuf(stdout, nil, _IONBF, 0)
        guard let index = arguments.firstIndex(of: "--office-snapshot"), index + 1 < arguments.count else { exit(2) }
        let url = URL(fileURLWithPath: arguments[index + 1])
        let zoom = arguments.firstIndex(of: "--zoom").flatMap { Double(arguments[$0 + 1]) }
        let live = arguments.contains("--live")
        model.loadDemoSessions()
        guard let resources = await Office3DResources.shared(), let scene = Office3DScene(resources: resources) else {
            print("office snapshot: varlıklar yüklenemedi"); exit(1)
        }
        let size = (width: 1600, height: 1000)
        scene.camera.viewSize = (Double(size.width), Double(size.height))
        let plan = model.officePlan()
        scene.camera.fit(plan)
        if let zoom {
            scene.camera.userMoved = true
            scene.camera.viewport.zoom = zoom
        }
        // `--focus-waiting`: kamera bekleyen ilk masaya (el sallama pozunu yakından görmek için).
        if arguments.contains("--focus-waiting"),
           let desk = plan.rooms.flatMap(\.desks).first(where: { if case .waiting = model.store.session($0.id)?.state { true } else { false } }) {
            let p = OfficeViewport.screenPlane(x: desk.x, y: 0.6, z: desk.z)
            scene.camera.userMoved = true
            scene.camera.viewport = OfficeViewport(centerX: p.x, centerY: p.y, zoom: zoom ?? 320)
        }
        let desks = demoDeskInfos(plan, model: model)
        if live { scene.update(plan: OfficePlan.make([], slots: [:]), desks: [:], look: model.look(for:), style: model.style(for:)) }
        scene.update(plan: plan, desks: desks, look: model.look(for:), style: model.style(for:))

        print("office snapshot: sahne kuruldu, \(desks.count) masa")
        let device = MTLCreateSystemDefaultDevice()!
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: size.width, height: size.height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = device.makeTexture(descriptor: descriptor)!
        for frame in 0..<45 {
            if frame % 15 == 0 { print("office snapshot: kare \(frame)") }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                do { try scene.renderFrame(to: texture, dt: 1.0 / 30) { continuation.resume() } }
                catch { print("render error \(error)"); continuation.resume() }
            }
        }
        let anchors = plan.rooms.flatMap(\.desks).map { OfficeOverlay.anchor($0, viewport: scene.camera.viewport, viewSize: scene.camera.viewSize) }
        do {
            try write(texture, anchors: anchors, to: url)
            print("office snapshot: \(url.path)")
            exit(0)
        } catch {
            print("office snapshot: \(error)"); exit(1)
        }
    }

    private static func demoDeskInfos(_ plan: OfficePlan, model: AppModel) -> [String: OfficeDeskInfo] {
        var result: [String: OfficeDeskInfo] = [:]
        for room in plan.rooms {
            for desk in room.desks {
                guard let session = model.store.session(desk.id) else { continue }
                result[desk.id] = OfficeDeskInfo(id: desk.id, title: session.title, state: session.state, kind: model.kind(of: desk.id),
                                                 roomKey: room.key, worktree: model.worktree(for: session.cwd), focused: false)
            }
        }
        return result
    }

    private static func write(_ texture: MTLTexture, anchors: [(x: Double, y: Double)], to url: URL) throws {
        let w = texture.width, h = texture.height, row = w * 4
        var bytes = [UInt8](repeating: 0, count: row * h)
        texture.getBytes(&bytes, bytesPerRow: row, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: row,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        for a in anchors {
            // CGContext sol alt orijinli; çapa sol üst orijinli nokta.
            ctx.fillEllipse(in: CGRect(x: a.x - 4, y: Double(h) - a.y - 4, width: 8, height: 8))
        }
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
}
