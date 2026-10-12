import Foundation
import simd

/// Karakter paketi (`tools/character` üretir, `Resources/Character/character.json` + `tex/`): iskelet, klipler ve modüler
/// parçalar (gövde, saç, üst, alt, ayakkabı; yüz ifadeleri dokudan). Mesh'ler uygulama uzayında (Y yukarı, +z ileri,
/// metre); köşe başına 4 kemik + ağırlık (u8, toplam 255). Paket yüklenemezse ofis çizicisi kurulmaz.
public struct CharacterArt: Sendable {
    public enum Mode: String, Codable, Sendable {
        /// Düz ton (ten) ya da sabit renk. `albedo`: doku. `tinted`: gri doku × ton (saç). `pattern`: görünüşün deseni
        /// (ya da parçanın dokusu) × ton. `eye`/`mouth`: ifade dokusu alfasıyla tona karışan opak çıkartma. `decal`:
        /// parçanın dokusuyla aynı (allık). `cutout`: doku, alfa < 0,5 atılır. `design`: tasarım kıyafeti — doku R ikinci
        /// renk maskesi, G gölge; `detail` dokusu (sabit renkli ayrıntı) üstüne; renkler görünüşten ya da `colors`'tan.
        case flat, albedo, tinted, pattern, eye, mouth, decal, cutout, design
    }

    /// `hat`: şapkanın rengi (seçilmemişse üstün rengi).
    public enum Tint: String, Codable, Sendable { case skin, hair, top, bottom, shoes, hat }

    public struct Part: Codable, Hashable, Sendable {
        public var mesh: String
        public var mode: Mode
        public var texture: String?
        public var tint: Tint?
        /// Tonsuz düz parçanın sabit rengi (sRGB).
        public var color: [Float]?
        /// Saçın tepe parçası (diken, topuz, bukle): şapka takılınca çizilmez.
        public var crown: Bool?
        /// `design`: sabit renkli ayrıntı dokusu ve tasarımın kendi iki rengi (sRGB).
        public var detail: String?
        public var colors: [[Float]]?
    }

    public struct Item: Codable, Sendable {
        public var name: String
        public var parts: [Part]
        /// Üst kıyafette: elbise/tulum (alt giyilmez).
        public var onepiece: Bool?
        /// Listede görünen ad (paket öğeleri; temel öğelerin adı uygulamada çevrilir) ve dillere göre çevirileri.
        public var title: String?
        public var titles: [String: String]?

        public init(name: String, parts: [Part], onepiece: Bool? = nil, title: String? = nil, titles: [String: String]? = nil) {
            self.name = name; self.parts = parts; self.onepiece = onepiece; self.title = title; self.titles = titles
        }

        /// Dile göre ad (ör. "tr"), yoksa İngilizce ad.
        public func title(language: String?) -> String? { language.flatMap { titles?[$0] } ?? title }

        /// Renkleri tasarımdan gelir (görünüşün palet renkleri değil, yalnız serbest renkler uygulanır).
        public var isDesign: Bool { parts.contains { $0.mode == .design } }
    }

    public struct Mesh: Sendable {
        public var vertexCount: Int
        public var positions: [Float]
        public var normals: [Float]
        public var uvs: [Float]
        public var joints: [UInt8]
        public var weights: [UInt8]
        public var indices: [UInt32]
    }

    public var directory: URL
    public var bones: [String]
    /// Ebeveyn indeksi (önce ebeveyn gelir; kökte -1) ve dinlenme pozunun dünya matrisleri (uygulama uzayı).
    public var parents: [Int]
    public var rest: [simd_float4x4]
    public var clips: [String: ArtClip]
    public var meshes: [String: Mesh]
    public var body: [Part]
    /// Yanaklar (allık açıkken çıkartma, kapalıyken düz ten).
    public var blush: [Part]
    public var hairs: [[Part]]
    public var hairNames: [String]
    public var hats: [Item]
    public var glasses: [Part]
    /// Göz stili → ifade dokuları (`eyeExpressions` sırası); ağız → ifade dokuları (paket içi göreli yol).
    public var eyes: [[String]]
    public var mouths: [[String]]
    public var patterns: [String]
    public var patternNames: [String]
    public var outfits: [Item]
    public var bottoms: [Item]
    public var shoes: [Item]
    /// Kalıp → temel paketteki karşılığı (paket kaldırılınca giyilen kıyafet buna düşer; ör. `coat` → `longsleeve`).
    public var fallbacks: [String: String]
    /// Kurulu paketler (kimlik → başlık), birleştirme sırasıyla.
    public var packs: [String] = []

    public static let fileName = "character.json"
    public static let packFileName = "pack.json"

    /// Uygulama paketindeki `Character` klasörü, yoksa depodaki `Resources/Character` (geliştirme).
    public static func find(bundleResources: URL?, repoRoot: URL, fileManager: FileManager = .default) -> URL? {
        [bundleResources?.appendingPathComponent("Character"), repoRoot.appendingPathComponent("Resources/Character")]
            .compactMap { $0 }
            .first { fileManager.fileExists(atPath: $0.appendingPathComponent(fileName).path) }
    }

    public static func load(directory: URL) throws -> CharacterArt {
        try decode(Data(contentsOf: directory.appendingPathComponent(fileName)), directory: directory)
    }

    public static func decode(_ data: Data, directory: URL) throws -> CharacterArt {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        typealias F = OfficeArtFile
        let boneCount = raw.bones.count
        let restFloats: [Float] = try F.array(raw.rest, "rest")
        guard raw.parents.count == boneCount, restFloats.count == boneCount * 16,
              raw.parents.enumerated().allSatisfy({ $0.element < $0.offset }) else { throw F.Failure.badLength("skeleton") }
        let rest: [simd_float4x4] = (0..<boneCount).map { b in
            let m = Array(restFloats[b * 16..<b * 16 + 16])
            return simd_float4x4(SIMD4(m[0], m[1], m[2], m[3]), SIMD4(m[4], m[5], m[6], m[7]), SIMD4(m[8], m[9], m[10], m[11]),
                                 SIMD4(m[12], m[13], m[14], m[15]))
        }
        var clips: [String: ArtClip] = [:]
        for (name, clip) in raw.clips {
            let matrices: [Float] = try F.array(clip.matrices, "clip \(name)")
            guard matrices.count == clip.frames * boneCount * 16 else { throw F.Failure.badLength("clip \(name)") }
            clips[name] = ArtClip(frames: clip.frames, matrices: matrices)
        }
        let meshes = try decodeMeshes(raw.meshes, boneCount: boneCount)
        let art = CharacterArt(directory: directory, bones: raw.bones, parents: raw.parents, rest: rest, clips: clips,
                               meshes: meshes, body: raw.body, blush: raw.blush, hairs: raw.hairs,
                               hairNames: raw.hairNames, hats: raw.hats, glasses: raw.glasses,
                               eyes: raw.eyes, mouths: raw.mouths, patterns: raw.patterns, patternNames: raw.patternNames,
                               outfits: raw.outfits, bottoms: raw.bottoms, shoes: raw.shoes, fallbacks: raw.fallbacks ?? [:])
        let referenced = art.body + art.blush + art.glasses + art.hairs.flatMap { $0 }
            + (art.outfits + art.bottoms + art.shoes + art.hats).flatMap(\.parts)
        if let missing = referenced.first(where: { meshes[$0.mesh] == nil }) { throw F.Failure.indexOutOfRange(missing.mesh) }
        guard !art.hairs.isEmpty, art.hairNames.count == art.hairs.count, !art.eyes.isEmpty, !art.mouths.isEmpty,
              !art.patterns.isEmpty, art.patternNames.count == art.patterns.count, !art.outfits.isEmpty, !art.bottoms.isEmpty,
              !art.shoes.isEmpty else { throw F.Failure.badLength("catalog") }
        return art
    }

    static func decodeMeshes(_ raw: [String: RawMesh], boneCount: Int) throws -> [String: Mesh] {
        typealias F = OfficeArtFile
        var meshes: [String: Mesh] = [:]
        for (name, m) in raw {
            let mesh = Mesh(vertexCount: m.vertexCount, positions: try F.array(m.positions, name), normals: try F.array(m.normals, name),
                            uvs: try F.array(m.uvs, name), joints: try F.array(m.joints, name), weights: try F.array(m.weights, name),
                            indices: try F.array(m.indices, name))
            let n = mesh.vertexCount
            guard mesh.positions.count == n * 3, mesh.normals.count == n * 3, mesh.uvs.count == n * 2,
                  mesh.joints.count == n * 4, mesh.weights.count == n * 4, mesh.indices.count % 3 == 0 else {
                throw F.Failure.badLength(name)
            }
            guard mesh.indices.allSatisfy({ Int($0) < n }), mesh.joints.allSatisfy({ Int($0) < boneCount }) else {
                throw F.Failure.indexOutOfRange(name)
            }
            meshes[name] = mesh
        }
        return meshes
    }

    /// İndirilebilir paket (`Packs/<kimlik>/pack.json` + `tex/`): ek kıyafet, alt, ayakkabı, şapka. Meshler aynı iskelete
    /// göre; mesh adları ve dokular paketin kimliğiyle ayrılır (dokular mutlak yol olur). Aynı adlı öğe paketinkiyle
    /// değişir.
    public mutating func merge(packAt directory: URL, id: String) throws {
        let raw = try JSONDecoder().decode(RawPack.self, from: Data(contentsOf: directory.appendingPathComponent(Self.packFileName)))
        let packMeshes = try Self.decodeMeshes(raw.meshes, boneCount: bones.count)
        func local(_ part: Part) -> Part {
            var p = part
            p.mesh = id + ":" + part.mesh
            p.texture = part.texture.map { directory.appendingPathComponent($0).path }
            p.detail = part.detail.map { directory.appendingPathComponent($0).path }
            return p
        }
        func items(_ list: [Item]?) -> [Item] {
            (list ?? []).map { Item(name: $0.name, parts: $0.parts.map(local), onepiece: $0.onepiece, title: $0.title, titles: $0.titles) }
        }
        let added = items(raw.outfits) + items(raw.bottoms) + items(raw.shoes) + items(raw.hats)
        if let missing = added.flatMap(\.parts).first(where: { packMeshes[String($0.mesh.dropFirst(id.count + 1))] == nil }) {
            throw OfficeArtFile.Failure.indexOutOfRange(missing.mesh)
        }
        for (name, mesh) in packMeshes { meshes[id + ":" + name] = mesh }
        func merged(_ base: [Item], _ extra: [Item]) -> [Item] {
            let names = Set(extra.map(\.name))
            return base.filter { !names.contains($0.name) } + extra
        }
        outfits = merged(outfits, items(raw.outfits))
        bottoms = merged(bottoms, items(raw.bottoms))
        shoes = merged(shoes, items(raw.shoes))
        hats = merged(hats, items(raw.hats))
        packs.append(id)
    }

    /// Kıyafet kimliği → katalog indeksi: tam ad; yoksa kalıp (`coat.tweed` → `coat`); yoksa temel karşılık
    /// (`fallbacks`, zincirlenebilir); yoksa ilk öğe.
    public func resolve(_ id: String, in items: [Item]) -> Int {
        let names = items.map(\.name)
        var name = id
        var seen: Set<String> = []
        while seen.insert(name).inserted {
            if let i = names.firstIndex(of: name) { return i }
            if let dot = name.firstIndex(of: ".") { name = String(name[..<dot]); continue }
            guard let next = fallbacks[name] else { break }
            name = next
        }
        return 0
    }

    /// Görünüşün kataloktaki karşılıkları (ad eşleşmezse kalıp / temel karşılık / ilk öğe).
    public struct Selection: Equatable, Sendable {
        public var hair, outfit, bottom, shoes, pattern, eyeStyle: Int
    }

    public func selection(for look: AvatarLook) -> Selection {
        func index(_ items: [String], _ name: String) -> Int { items.firstIndex(of: name) ?? 0 }
        let eyeStyle: Int = switch look.eyes {
        case .dot: 0
        case .round: 1
        case .lashes: 2
        case .sleepy: 3
        case .happy: 4
        case .brows: 5
        }
        return Selection(hair: index(hairNames, look.hairStyle.rawValue), outfit: resolve(look.top, in: outfits),
                         bottom: resolve(look.bottom, in: bottoms), shoes: resolve(look.shoes, in: shoes),
                         pattern: index(patternNames, look.shirtPattern.rawValue), eyeStyle: Self.wrap(eyeStyle, eyes.count))
    }

    /// Bir görünüşün çizilecek parçaları: gövde + yanaklar + saç (şapka varsa tepe parçası olmadan) + üst +
    /// (elbise/tulum değilse) alt + ayakkabı + (varsa) gözlük.
    public func parts(for look: AvatarLook) -> [Part] {
        let s = selection(for: look)
        let outfit = outfits[s.outfit]
        let hat = look.hat == .none ? nil : hats.first { $0.name == look.hat.rawValue }
        var parts = body + blush + hairs[s.hair].filter { hat == nil || $0.crown != true } + outfit.parts
        if outfit.onepiece != true { parts += bottoms[s.bottom].parts }
        parts += shoes[s.shoes].parts
        if let hat { parts += hat.parts }
        if look.glasses { parts += glasses }
        return parts
    }

    public func eyeTexture(style: Int, expression: Int) -> String {
        let layers = eyes[Self.wrap(style, eyes.count)]
        return layers[Self.wrap(expression, layers.count)]
    }

    public func mouthTexture(expression: Int) -> String {
        let layers = mouths[0]
        return layers[Self.wrap(expression, layers.count)]
    }

    static func wrap(_ i: Int, _ n: Int) -> Int { n == 0 ? 0 : ((i % n) + n) % n }

    /// Klipler için iskelet (geçişler ebeveyne göre yerel uzayda karışır).
    public var skeleton: VillagerSkeleton {
        VillagerSkeleton(boneCount: bones.count, clips: clips, hierarchy: .init(parents: parents, rest: rest))
    }

    struct Raw: Decodable {
        var bones: [String]
        var parents: [Int]
        var rest: String
        var clips: [String: OfficeArtFile.RawClip]
        var meshes: [String: RawMesh]
        var body: [Part]
        var blush: [Part]
        var hairs: [[Part]]
        var hairNames: [String]
        var hats: [Item]
        var glasses: [Part]
        var eyes: [[String]]
        var mouths: [[String]]
        var patterns: [String]
        var patternNames: [String]
        var outfits: [Item]
        var bottoms: [Item]
        var shoes: [Item]
        var fallbacks: [String: String]?
    }

    struct RawPack: Decodable {
        var meshes: [String: RawMesh]
        var outfits, bottoms, shoes, hats: [Item]?
    }

    struct RawMesh: Decodable {
        var vertexCount: Int
        var positions, normals, uvs, joints, weights, indices: String
    }
}
