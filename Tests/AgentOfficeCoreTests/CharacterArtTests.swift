import Foundation
import simd
import Testing
@testable import AgentOfficeCore

/// Karakter paketi (CharacterArt): çözüm, bozuk paket, katalog seçimi ve depodaki gerçek paket.
@Suite struct CharacterArtTests {
    static func b64<T>(_ values: [T]) -> String { values.withUnsafeBytes { Data($0).base64EncodedString() } }

    /// 2 kemik, 1 üçgenlik mesh ve 1 karelik `idle`.
    static func pack(joints: [UInt8] = [0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], index: UInt32 = 2, frames: Int = 1,
                     parents: [Int] = [-1, 0], fallbacks: [String: String] = [:]) -> Data {
        let mesh: [String: Any] = [
            "vertexCount": 3, "positions": b64([Float](repeating: 0, count: 9)), "normals": b64([Float](repeating: 0, count: 9)),
            "uvs": b64([Float](repeating: 0, count: 6)), "joints": b64(joints), "weights": b64([UInt8](repeating: 0, count: 12)),
            "indices": b64([UInt32]([0, 1, index])),
        ]
        let identity: [Float] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        func part(_ mode: String, _ tint: String? = nil) -> [String: Any] { tint.map { ["mesh": "m", "mode": mode, "tint": $0] } ?? ["mesh": "m", "mode": mode] }
        let crownPart: [String: Any] = ["mesh": "m", "mode": "tinted", "tint": "hair", "crown": true]
        let json: [String: Any] = [
            "bones": ["Root", "Head"], "parents": parents, "rest": b64(identity + identity),
            "clips": ["idle": ["frames": frames, "matrices": b64(identity + identity)]],
            "meshes": ["m": mesh], "body": [part("flat", "skin"), part("eye", "skin"), part("mouth", "skin")],
            "blush": [part("decal", "skin")], "hairs": [[part("tinted", "hair")], [part("tinted", "hair"), crownPart]],
            "hats": [["name": "cap", "parts": [part("flat", "top")]]], "glasses": [part("flat")],
            "hairNames": ["short", "bob"], "eyes": [["e0", "e1"], ["f0", "f1"]], "mouths": [["m0", "m1"]],
            "patterns": ["p0", "p1"], "patternNames": ["plain", "stripes"],
            "outfits": [["name": "tee", "parts": [part("pattern", "top")]], ["name": "dress", "parts": [part("pattern", "top")], "onepiece": true]],
            "bottoms": [["name": "pants", "parts": [part("flat", "bottom")]]], "shoes": [["name": "sneakers", "parts": [part("flat", "shoes")]]],
            "fallbacks": fallbacks,
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test func decodesAndSelectsByLook() throws {
        let art = try CharacterArt.decode(Self.pack(), directory: URL(fileURLWithPath: "/tmp"))
        #expect(art.bones == ["Root", "Head"] && art.skeleton.boneCount == 2)
        var look = AvatarLook.default(for: "x")
        look.hairStyle = .bob; look.top = "tee"; look.shirtPattern = .stripes; look.eyes = .round
        look.hat = .none; look.glasses = false
        let s = art.selection(for: look)
        #expect(s.hair == 1 && s.outfit == 0 && s.pattern == 1 && s.eyeStyle == 1)
        // Tişört: gövde + yanak + saç (taban + tepe) + üst + alt + ayakkabı; elbise: alt yok.
        #expect(art.parts(for: look).count == 3 + 1 + 2 + 1 + 1 + 1)
        look.top = "dress"
        #expect(art.parts(for: look).count == 3 + 1 + 2 + 1 + 1)
        // Şapka (katalogda varsa) saçın tepesini gizler; şapka ve gözlük birer parça ekler.
        look.hat = .cap; look.glasses = true
        #expect(art.parts(for: look).count == 3 + 1 + 1 + 1 + 1 + 1 + 1)
        look.hat = .beanie   // katalogda yok: eklenmez, tepe gizlenmez
        #expect(art.parts(for: look).count == 3 + 1 + 2 + 1 + 1 + 1)
        // Katalogda olmayan ad → ilk öğe.
        look.hairStyle = .spiky
        #expect(art.selection(for: look).hair == 0)
        #expect(art.eyeTexture(style: 1, expression: 3) == "f1" && art.mouthTexture(expression: 1) == "m1")
    }

    @Test func rejectsCorruptPacks() {
        let dir = URL(fileURLWithPath: "/tmp")
        #expect(throws: OfficeArtFile.Failure.self) { try CharacterArt.decode(Self.pack(joints: [UInt8](repeating: 7, count: 12)), directory: dir) }
        #expect(throws: OfficeArtFile.Failure.self) { try CharacterArt.decode(Self.pack(index: 9), directory: dir) }
        #expect(throws: OfficeArtFile.Failure.self) { try CharacterArt.decode(Self.pack(frames: 3), directory: dir) }
        #expect(throws: OfficeArtFile.Failure.self) { try CharacterArt.decode(Self.pack(parents: [1, -1]), directory: dir) }
    }

    /// Depodaki paket: bütün klipler, makul poligon bütçesi, her görünüş seçeneğinin karşılığı.
    @Test func realPackIsSane() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = try #require(CharacterArt.find(bundleResources: nil, repoRoot: root))
        let art = try CharacterArt.load(directory: dir)
        for clip in AvatarClip.allCases { #expect(art.clips[clip.rawValue] != nil, "\(clip)") }
        for style in AvatarLook.HairStyle.allCases { #expect(art.hairNames.contains(style.rawValue), "\(style)") }
        #expect(Set(AvatarLook.Top.allCases.map(\.rawValue)).isSubset(of: art.outfits.map(\.name)))
        #expect(Set(AvatarLook.Bottom.allCases.map(\.rawValue)).isSubset(of: art.bottoms.map(\.name)))
        #expect(Set(AvatarLook.Shoes.allCases.map(\.rawValue)).isSubset(of: art.shoes.map(\.name)))
        #expect(Set(AvatarLook.ShirtPattern.allCases.map(\.rawValue)).isSubset(of: art.patternNames))
        #expect(art.eyes.count == AvatarLook.Eyes.allCases.count)
        #expect(Set(AvatarLook.Hat.allCases.filter { $0 != .none }.map(\.rawValue)).isSubset(of: art.hats.map(\.name)))
        #expect(!art.glasses.isEmpty)
        // Hafif: bir karakter (en ağır seçimlerle) 8 bin üçgenin altında.
        let tris = { (parts: [CharacterArt.Part]) in parts.reduce(0) { $0 + (art.meshes[$1.mesh]?.indices.count ?? 0) / 3 } }
        let heaviest = art.body + art.blush + art.hairs.max { tris($0) < tris($1) }! + art.outfits.flatMap(\.parts).prefix(2)
            + art.bottoms[0].parts + art.shoes[0].parts
        #expect(tris(heaviest) < 8000)
        for path in art.eyes.flatMap({ $0 }) + art.mouths.flatMap({ $0 }) + art.patterns {
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(path).path), "\(path)")
        }
    }

    @Test func oldLooksDecodeWithNewFields() throws {
        // Önceki sürümün kaydı: yeni alanlar yok → varsayılanlar.
        let json = #"{"hairStyle":"bob","hairColor":1,"skin":2,"shirtPattern":"dots","glasses":false}"#
        let look = try JSONDecoder().decode(AvatarLook.self, from: Data(json.utf8))
        #expect(look.top == "tee" && look.bottom == "pants" && look.shoes == "sneakers" && look.hairStyle == .bob)
        var custom = look
        custom.top = "overalls"; custom.shoes = "boots"; custom.hairStyle = .ponytail; custom.shirtPattern = .plaid
        #expect(try JSONDecoder().decode(AvatarLook.self, from: JSONEncoder().encode(custom)) == custom)
        // Varsayılan görünüşün eski alanları değişmedi (desen ilk üçten), kıyafet türleri çeşitli.
        let looks = (0..<200).map { AvatarLook.default(for: "session-\($0)") }
        #expect(Set(looks.map(\.shirtPattern)).isSubset(of: [.plain, .stripes, .dots]))
        #expect(Set(looks.map(\.top)).count >= 5 && Set(looks.map(\.shoes)).count == 3)
    }
}

/// Hiyerarşili iskelette geçişler kemik boyunu korur (skinning matrisleri ayrı ayrı karıştırılınca
/// omuz/dirsek pivotu kayıyor, kol kopuyordu).
@Suite struct HierarchySkeletonTests {
    /// İki kemik: kök (0,0,0), çocuk (1,0,0). `idle`: dinlenme; `wave`: kök z'de 90°, çocuk kendi ekleminde 90°.
    static func skeleton() -> VillagerSkeleton {
        func rotZ(_ deg: Float, about p: SIMD3<Float>) -> simd_float4x4 {
            var r = simd_float4x4(simd_quatf(angle: deg * .pi / 180, axis: SIMD3(0, 0, 1)))
            r.columns.3 = SIMD4(p - simd_make_float3(r * SIMD4(p, 1)), 1)
            return r
        }
        let rootB = rotZ(90, about: .zero)
        let childB = rootB * rotZ(90, about: SIMD3(1, 0, 0))
        func flat(_ ms: [simd_float4x4]) -> [Float] { ms.flatMap { m in (0..<4).flatMap { c in (0..<4).map { m[c][$0] } } } }
        var rest1 = matrix_identity_float4x4
        rest1.columns.3 = SIMD4(1, 0, 0, 1)
        let id = matrix_identity_float4x4
        return VillagerSkeleton(boneCount: 2,
                                clips: ["idle": ArtClip(frames: 2, matrices: flat([id, id, id, id])),
                                        "wave": ArtClip(frames: 2, matrices: flat([rootB, childB, rootB, childB]))],
                                hierarchy: .init(parents: [-1, 0], rest: [id, rest1]))
    }

    @Test func crossfadeKeepsChildAttachedToParent() {
        let s = Self.skeleton()
        var a = AvatarInstance(id: "x", clip: .idle)
        a.play(.wave, skeleton: s)
        for step in 1...9 {
            a.advance(dt: AvatarInstance.fade / 10)
            let m = s.pose(of: a)
            // Çocuğun eklemi (1,0,0) hem kökün hem kendi matrisiyle aynı yere gitmeli.
            let viaParent = simd_make_float3(m[0] * SIMD4(1, 0, 0, 1))
            let viaChild = simd_make_float3(m[1] * SIMD4(1, 0, 0, 1))
            #expect(simd_distance(viaParent, viaChild) < 1e-4, "adım \(step)")
        }
        // Geçiş bitince klibin kendisi.
        a.advance(dt: 1)
        let end = s.pose(of: a)
        #expect(simd_distance(simd_make_float3(end[1] * SIMD4(2, 0, 0, 1)), SIMD3(-1, 1, 0)) < 1e-4)
    }
}

/// Tepkiler: bekleme türüne göre hareket, ifade ve baş üstü efekti.
@Suite struct ReactionTests {
    @Test func effectFollowsClipAndWaiting() {
        #expect(AvatarEffect.current(clip: .wave, waitReason: .permission, clipTime: 0) == .sweat)
        #expect(AvatarEffect.current(clip: .wave, waitReason: .question, clipTime: 0) == nil)
        #expect(AvatarEffect.current(clip: .notice, waitReason: .question, clipTime: 0) == .notice)
        #expect(AvatarEffect.current(clip: .cheer, waitReason: nil, clipTime: 0) == .sparkle)
        #expect(AvatarEffect.current(clip: .sitDoze, waitReason: nil, clipTime: 0) == .sleep)
        #expect(AvatarEffect.current(clip: .sitType, waitReason: nil, clipTime: 0) == nil)
    }

    @Test func spritesStayVisibleAndBounded() {
        for effect in AvatarEffect.allCases {
            for t in stride(from: 0.0, to: 5, by: 0.05) {
                let sprites = effect.sprites(time: t)
                #expect(!sprites.isEmpty)
                #expect(sprites.allSatisfy { (0...1).contains($0.alpha) && $0.size > 0 && $0.size < 0.4 && simd_length($0.offset) < 0.6 })
            }
        }
    }

    @Test func questionTriggersNoticeAndPermissionScratches() {
        var b = AvatarBehavior(id: "a")
        b.setActivity(.waving, finishedNow: false)
        b.setWaitReason(.question)
        _ = b.advance(dt: 0.01, freeSpots: [])   // hedef: masanın yanında dur
        var shots: [AvatarClip] = []
        for _ in 0..<60 { if case .oneShot(let c)? = b.advance(dt: 0.1, freeSpots: []) { shots.append(c) } }
        #expect(shots.first == .notice)

        var p = AvatarBehavior(id: "b")
        p.setActivity(.waving, finishedNow: false)
        p.setWaitReason(.permission)
        _ = p.advance(dt: 0.01, freeSpots: [])
        var picks: [AvatarClip] = []
        for _ in 0..<2000 { if case .oneShot(let c)? = p.advance(dt: 0.1, freeSpots: []) { picks.append(c) } }
        #expect(picks.contains(.scratchHead) && !picks.contains(.lookAround) && !picks.contains(.notice))
    }

    @Test func faceFollowsClipWaitingAndRestingMouth() {
        typealias E = AvatarExpression
        let seed: UInt64 = 123_456
        let t = stride(from: 0.2, to: 6, by: 0.05).first { !E.blinking(time: $0, seed: seed) }!
        func face(_ c: AvatarClip, _ r: AvatarInstance.WaitReason? = nil, rest: Int = E.smile) -> E.Face {
            E.face(clip: c, waitReason: r, restingMouth: rest, time: t, seed: seed)
        }
        #expect(face(.wave, .permission) == .init(eye: E.worriedEyes, mouth: E.worried))
        #expect(face(.notice, .question) == .init(eye: E.wide, mouth: E.wow))
        #expect(face(.walk, .question) == .init(eye: E.wide, mouth: E.ooh))
        #expect(face(.cheer) == .init(eye: E.happy, mouth: E.laugh))
        #expect(face(.sitType) == .init(eye: E.focused, mouth: E.flat))
        #expect(face(.idle, rest: E.resting(.flat)) == .init(eye: E.normal, mouth: E.flat))
        // Göz kırpma kısa ve dönemli; kapalı/mutlu gözler değişmez.
        let blink = stride(from: 0.0, to: 10, by: 0.01).first { E.blinking(time: $0, seed: seed) }!
        #expect(E.face(clip: .idle, waitReason: nil, restingMouth: E.smile, time: blink, seed: seed).eye == E.closed)
        #expect(E.face(clip: .cheer, waitReason: nil, restingMouth: E.smile, time: blink, seed: seed).eye == E.happy)
        let samples = stride(from: 0.0, to: 30, by: 0.01).map { E.blinking(time: $0, seed: seed) }
        let closed = Double(samples.filter { $0 }.count) / Double(samples.count)
        #expect(closed > 0.01 && closed < 0.06)
    }
}
