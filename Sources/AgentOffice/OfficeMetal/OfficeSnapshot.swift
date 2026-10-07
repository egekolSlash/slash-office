import AgentOfficeCore
import AppKit
import Metal
import SwiftUI

/// `AgentOffice --office-snapshot <png> [--zoom <z>] [--live] [--focus-waiting] [--custom] [--bench <fps>] [--anchors]` (kartlar SwiftUI katmanından eklenir; --anchors çapaları kırmızı noktayla gösterir): demo ofisini ekran dışı çizip PNG yazar ve çıkar.
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
        // `--custom`: özelleştirmenin sahneye yansıdığını görmek için bir köylüye ve odaya özel görünüm.
        if arguments.contains("--custom") {
            model.avatarLooks["demo-0"] = AvatarLook(hairStyle: .pigtails, hairColor: 5, skin: 2, shirtPattern: .dots, shirtColor: 3, glasses: true)
            model.roomStyles["/demo/juice-merge"] = RoomStyle(wallpaper: 2, floor: 2, rug: .plain)
        }
        guard let gpu = await OfficeGPU.shared(), let renderer = try? OfficeMetalRenderer(gpu: gpu) else {
            print("office snapshot: varlıklar yüklenemedi"); exit(1)
        }
        let size = (width: 1600, height: 1000)
        let camera = OfficeCamera()
        camera.viewSize = (Double(size.width), Double(size.height))
        let plan = model.officePlan()
        camera.fit(plan)
        if let zoom {
            camera.userMoved = true
            camera.viewport.zoom = zoom
        }
        // `--focus-waiting`: kamera bekleyen ilk masaya (el sallama pozunu yakından görmek için).
        if arguments.contains("--focus-waiting"),
           let desk = plan.rooms.flatMap(\.desks).first(where: { if case .waiting = model.store.session($0.id)?.state { true } else { false } }) {
            let p = OfficeViewport.screenPlane(x: desk.x, y: 0.6, z: desk.z)
            camera.userMoved = true
            camera.viewport = OfficeViewport(centerX: p.x, centerY: p.y, zoom: zoom ?? 320)
        }
        let desks = demoDeskInfos(plan, model: model)
        let colors = Dictionary(uniqueKeysWithValues: plan.rooms.map { room in
            let c = ProjectPalette.colors[ProjectPalette.index(for: room.key)]
            return (room.key, (red: c.red, green: c.green, blue: c.blue))
        })
        let terminals = Set(desks.values.filter { $0.kind == .shell }.map(\.id))
        let mesh = OfficeWorldBuilder.build(plan: plan, terminalDesks: terminals, style: model.style(for:),
                                            projectColor: { colors[$0] ?? (0.6, 0.6, 0.6) }, art: gpu.art)
        renderer.setWorld(mesh, plan: plan.bounds)
        var sim = AvatarSim(skeleton: gpu.skeleton)
        let states = desks.mapValues { AvatarDeskState(state: $0.state, kind: $0.kind) }
        let looks = Dictionary(uniqueKeysWithValues: desks.keys.map { ($0, model.look(for: $0)) })
        if live { sim.sync(plan: OfficePlan.make([], slots: [:]), desks: [:], looks: [:], projectColors: [:], live: false) }
        sim.sync(plan: plan, desks: states, looks: looks, projectColors: colors, live: live)
        print("office snapshot: sahne kuruldu, \(desks.count) masa, \(mesh.vertices.count) köşe")

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: OfficeGPU.colorFormat, width: size.width, height: size.height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = gpu.device.makeTexture(descriptor: descriptor)!
        var time = 0.0
        func renderFrame(dt: Double) async {
            time += dt
            sim.tick(dt: dt)
            let cb = gpu.queue.makeCommandBuffer()!
            renderer.encode(to: texture, viewport: camera.viewport, viewSize: camera.viewSize, avatars: sim.instances,
                            time: time, commandBuffer: cb)
            let (done, finish) = AsyncStream<Void>.makeStream()
            cb.addCompletedHandler { _ in finish.finish() }
            cb.commit()
            for await _ in done {}
        }
        // `--bench <fps>`: ölçüm için ekran dışında bu kare hızında 20 sn çizer (pencere başka Space'teyken de çalışır).
        if let i = arguments.firstIndex(of: "--bench"), let fps = Double(arguments[i + 1]) {
            print("office bench: \(fps) fps, 20 sn")
            let end = Date().addingTimeInterval(20)
            while Date() < end {
                let start = Date()
                await renderFrame(dt: 1 / fps)
                let wait = 1 / fps - Date().timeIntervalSince(start)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            }
            exit(0)
        }
        for _ in 0..<45 { await renderFrame(dt: 1.0 / 30) }
        let anchors = plan.rooms.flatMap(\.desks).map { OfficeOverlay.anchor($0, viewport: camera.viewport, viewSize: camera.viewSize) }
        // SwiftUI kart katmanı (tabelalar, kartlar, ? ve ✓ balonları) da resme eklenir.
        let cards = ImageRenderer(content: OfficeCards(plan: plan, desks: desks, camera: camera, icons: model.projectIcons, interactive: true)
            .frame(width: CGFloat(size.width), height: CGFloat(size.height)))
        cards.scale = 1
        do {
            try write(texture, anchors: arguments.contains("--anchors") ? anchors : [], overlay: cards.cgImage, to: url)
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
                                                 roomKey: room.key, worktree: model.worktree(for: session.cwd), focused: false, summary: session.workSummary, unseenFinish: session.unseenFinish)
            }
        }
        return result
    }

    private static func write(_ texture: MTLTexture, anchors: [(x: Double, y: Double)], overlay: CGImage?, to url: URL) throws {
        let w = texture.width, h = texture.height, row = w * 4
        var bytes = [UInt8](repeating: 0, count: row * h)
        texture.getBytes(&bytes, bytesPerRow: row, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: row,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        if let overlay { ctx.draw(overlay, in: CGRect(x: 0, y: 0, width: w, height: h)) }
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        for a in anchors {
            // CGContext sol alt orijinli; çapa sol üst orijinli nokta.
            ctx.fillEllipse(in: CGRect(x: a.x - 4, y: Double(h) - a.y - 4, width: 8, height: 8))
        }
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
}
