import AgentOfficeCore
import AppKit
import Metal

/// `AgentOffice --villager-frames <spec.json> <klasör>`: tek tek köylüleri ofisin çizicisiyle ekran dışında, saydam arka
/// planda çizip kare kare PNG yazar ve çıkar (tanıtım videosu için; hook sunucusu ve oturumlar başlamaz).
///
/// Spec: `{"size": [w, h], "fps": 30, "shots": [{"name", "frames", "desk": bool, "zoom": çarpan,
/// "room": {"key", "style": RoomStyle, "color": [r, g, b]}, "villagers": [{"look": AvatarLook, "shirt": [r, g, b],
/// "facing": radyan, "offset": [x, z], "wait": "question" | "permission", "clips": [{"clip", "at": kare}]}]}]}`.
/// Her çekim `<klasör>/<name>/0000.png …` olur; `--only a,b` yalnız bu çekimleri çizer.
@MainActor
enum VillagerFrames {
    static func requested(_ arguments: [String]) -> Bool { arguments.contains("--villager-frames") }

    struct Spec: Decodable {
        var size: [Int]
        var fps: Double?
        var shots: [Shot]
    }

    struct Shot: Decodable {
        var name: String
        var frames: Int
        /// Tek köylünün önünde masa (oda yokken).
        var desk: Bool?
        var zoom: Double?
        /// Oda çekimi: tek odalı plan, köylüler sırayla masalara oturur; kamera odanın ortasına.
        var room: Room?
        /// Oda çekiminde kameranın baktığı plan noktası [x, z]; yoksa odanın ortası.
        var target: [Double]?
        var villagers: [Villager]
    }

    struct Room: Decodable {
        var key: String
        var style: RoomStyle
        var color: [Double]
    }

    struct Villager: Decodable {
        var look: AvatarLook
        var shirt: [Float]
        var facing: Float?
        /// Konuma eklenen kayma [x, z] (ör. masanın yanında ayakta).
        var offset: [Float]?
        var wait: String?
        var clips: [Cue]
    }

    struct Cue: Decodable {
        var clip: String
        var at: Int
    }

    static func run(arguments: [String]) async {
        setvbuf(stdout, nil, _IONBF, 0)
        guard let i = arguments.firstIndex(of: "--villager-frames"), i + 2 < arguments.count,
              let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[i + 1])) else {
            print("usage: --villager-frames <spec.json> <out-dir>"); exit(2)
        }
        let out = URL(fileURLWithPath: arguments[i + 2], isDirectory: true)
        let only = arguments.firstIndex(of: "--only").map { Set(arguments[$0 + 1].split(separator: ",").map(String.init)) }
        let spec: Spec
        do { spec = try JSONDecoder().decode(Spec.self, from: data) } catch { print("villager frames: \(error)"); exit(2) }
        guard let gpu = await OfficeGPU.shared(), let renderer = try? OfficeMetalRenderer(gpu: gpu) else {
            print("villager frames: assets could not be loaded"); exit(1)
        }
        renderer.transparentBackground = true
        renderer.setLighting(OfficeDaylight.at(hour: 13))
        let size = (width: spec.size[0], height: spec.size[1])
        let viewSize = (width: Double(size.width), height: Double(size.height))
        let fps = spec.fps ?? 30
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: OfficeGPU.colorFormat, width: size.width,
                                                                  height: size.height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = gpu.device.makeTexture(descriptor: descriptor)!

        for shot in spec.shots where only?.contains(shot.name) ?? true {
            var instances = shot.villagers.enumerated().map { k, v in
                var instance = AvatarInstance(id: "\(shot.name)-\(k)", clip: .idle)
                instance.look = v.look
                instance.shirtColor = SIMD3(v.shirt[0], v.shirt[1], v.shirt[2])
                instance.facing = v.facing ?? 0
                instance.waitReason = v.wait == "question" ? .question : v.wait == "permission" ? .permission : nil
                return instance
            }
            let base = VillagerPreviewNSView.viewport(viewSize)
            let zoom = base.zoom * (shot.zoom ?? 1)
            let viewport: OfficeViewport
            if let room = shot.room {
                // Tek odalı plan: dünya kurucusu odayı, masaları ve çevresini oyundaki gibi kurar.
                let members = instances.map { OfficePlan.Member(id: $0.id, roomKey: room.key) }
                let plan = OfficePlan.make(members, slots: OfficePlan.assignSlots(members, previous: [:]))
                let color = (red: room.color[0], green: room.color[1], blue: room.color[2])
                let mesh = OfficeWorldBuilder.build(plan: plan, terminalDesks: [], style: { _ in room.style },
                                                    projectColor: { _ in color }, art: gpu.art)
                renderer.setWorld(mesh, site: OfficeWorldBuilder.siteRect(plan))
                guard let planRoom = plan.rooms.first else { continue }
                for k in instances.indices {
                    guard let desk = planRoom.desks.first(where: { $0.id == instances[k].id }) else { continue }
                    let seat = planRoom.seat(for: desk)
                    instances[k].position = SIMD3(Float(seat.x), 0, Float(seat.z))
                    if shot.villagers[k].facing == nil { instances[k].facing = Float(planRoom.seatFacing(for: desk)) }
                }
                let target = shot.target ?? [planRoom.x + planRoom.width / 2, planRoom.z + planRoom.depth / 2]
                viewport = CameraFollow.target(x: target[0], z: target[1], seated: true, zoom: zoom, fit: base)
            } else {
                // Masa (0, 0)'da, köylü masanın arkasında oturur ve kameraya bakar; ayaktaysa (0, 0)'da durur.
                let desk = shot.desk ?? false
                var mesh = OfficeMesh()
                if desk, let prop = gpu.art.props["desk_set"] { mesh.append(prop, at: .zero, yaw: 0) }
                renderer.setWorld(mesh, site: PlanRect(minX: -1.5, minZ: -1.5, maxX: 1.5, maxZ: 1.5))
                let z = desk ? -DeskGeometry.seatOffset : 0
                for k in instances.indices {
                    let o = shot.villagers[k].offset ?? [0, 0]
                    instances[k].position = SIMD3(o[0], 0, Float(z) + o[1])
                }
                viewport = CameraFollow.target(x: 0, z: z, seated: desk, zoom: zoom, fit: base)
            }
            let dir = out.appendingPathComponent(shot.name, isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var time = 0.0
            for frame in 0..<shot.frames {
                for k in instances.indices {
                    let cues = shot.villagers[k].clips
                    if let cue = cues.last(where: { $0.at == frame }) ?? (frame == 0 ? cues.first : nil),
                       let clip = AvatarClip(rawValue: cue.clip) {
                        instances[k].play(clip, skeleton: gpu.skeleton)
                        // İlk karede geçiş olmasın: doğrudan klibin pozu.
                        if frame == 0 { instances[k].blend = 1; instances[k].previousClip = nil }
                    }
                    instances[k].advance(dt: frame == 0 ? 0 : 1 / fps)
                }
                time += 1 / fps
                guard let cb = gpu.queue.makeCommandBuffer() else { exit(1) }
                renderer.encode(to: texture, viewport: viewport, viewSize: viewSize, avatars: instances, time: time, commandBuffer: cb)
                await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                    cb.addCompletedHandler { _ in done.resume() }
                    cb.commit()
                }
                do {
                    try write(texture, to: dir.appendingPathComponent(String(format: "%04d.png", frame)))
                } catch {
                    print("villager frames: \(error)"); exit(1)
                }
            }
            print("villager frames: \(shot.name) \(shot.frames)")
        }
        exit(0)
    }

    private static func write(_ texture: MTLTexture, to url: URL) throws {
        let w = texture.width, h = texture.height, row = w * 4
        var bytes = [UInt8](repeating: 0, count: row * h)
        texture.getBytes(&bytes, bytesPerRow: row, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: row,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
}
