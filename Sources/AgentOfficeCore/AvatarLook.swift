/// Köylünün görünüşü (spec §4; ofis hayatı §C1). Varsayılanı oturum kimliğinden türer; kullanıcı değiştirebilir.
public struct AvatarLook: Codable, Equatable, Hashable, Sendable {
    public typealias RGBA = (red: Double, green: Double, blue: Double)
    public enum HairStyle: String, Codable, CaseIterable, Sendable { case short, pigtails, spiky, bob, curly, long, bun }
    public enum ShirtPattern: String, Codable, CaseIterable, Sendable { case plain, stripes, dots }
    public enum Hat: String, Codable, CaseIterable, Sendable { case none, beanie, cap, headphones }
    public enum Eyes: String, Codable, CaseIterable, Sendable { case round, happy, sleepy }
    public enum Brows: String, Codable, CaseIterable, Sendable { case none, thin, bold }
    public enum Mouth: String, Codable, CaseIterable, Sendable { case smile, open, flat }

    /// Kullanıcının verdiği isim (kartta ve listede oturum başlığının yerine); yoksa nil.
    public var name: String?
    public var hairStyle: HairStyle
    public var hairColor: Int
    public var skin: Int
    public var shirtPattern: ShirtPattern
    /// `nil`: projenin rengi.
    public var shirtColor: Int?
    public var glasses: Bool
    public var hat: Hat
    public var pantsColor: Int
    public var shoeColor: Int
    public var eyes: Eyes
    public var brows: Brows
    public var mouth: Mouth
    public var freckles: Bool
    /// Yanak allığı (bugünkü köylülerde var).
    public var blush: Bool

    public init(hairStyle: HairStyle, hairColor: Int, skin: Int, shirtPattern: ShirtPattern, shirtColor: Int?, glasses: Bool,
                name: String? = nil, hat: Hat = .none, pantsColor: Int = 0, shoeColor: Int = 0, eyes: Eyes = .round,
                brows: Brows = .none, mouth: Mouth = .smile, freckles: Bool = false, blush: Bool = true) {
        self.hairStyle = hairStyle; self.hairColor = hairColor; self.skin = skin
        self.shirtPattern = shirtPattern; self.shirtColor = shirtColor; self.glasses = glasses
        self.name = name; self.hat = hat; self.pantsColor = pantsColor; self.shoeColor = shoeColor
        self.eyes = eyes; self.brows = brows; self.mouth = mouth; self.freckles = freckles; self.blush = blush
    }

    enum CodingKeys: String, CodingKey {
        case name, hairStyle, hairColor, skin, shirtPattern, shirtColor, glasses, hat, pantsColor, shoeColor
        case eyes, brows, mouth, freckles, blush
    }

    /// Eski kayıtlarda yeni alanlar yok: bugünkü görünüme karşılık gelen değerler.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(hairStyle: try c.decode(HairStyle.self, forKey: .hairStyle),
                  hairColor: try c.decode(Int.self, forKey: .hairColor),
                  skin: try c.decode(Int.self, forKey: .skin),
                  shirtPattern: try c.decode(ShirtPattern.self, forKey: .shirtPattern),
                  shirtColor: try c.decodeIfPresent(Int.self, forKey: .shirtColor),
                  glasses: try c.decode(Bool.self, forKey: .glasses),
                  name: try c.decodeIfPresent(String.self, forKey: .name).flatMap(Self.trimmedName),
                  hat: try c.decodeIfPresent(Hat.self, forKey: .hat) ?? .none,
                  pantsColor: try c.decodeIfPresent(Int.self, forKey: .pantsColor) ?? 0,
                  shoeColor: try c.decodeIfPresent(Int.self, forKey: .shoeColor) ?? 0,
                  eyes: try c.decodeIfPresent(Eyes.self, forKey: .eyes) ?? .round,
                  brows: try c.decodeIfPresent(Brows.self, forKey: .brows) ?? .none,
                  mouth: try c.decodeIfPresent(Mouth.self, forKey: .mouth) ?? .smile,
                  freckles: try c.decodeIfPresent(Bool.self, forKey: .freckles) ?? false,
                  blush: try c.decodeIfPresent(Bool.self, forKey: .blush) ?? true)
    }

    /// Kartta ve listede gösterilen ad: köylünün adı, yoksa oturum başlığı.
    public func displayName(title: String) -> String { name ?? title }
    /// Ad verilmişse oturum başlığı (proje) altta küçük gösterilir.
    public func subtitle(title: String) -> String? { name == nil ? nil : title }

    /// Boş ya da sadece boşluksa nil.
    public static func trimmedName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static let hairColors: [RGBA] = [
        (0.30, 0.16, 0.08), (0.12, 0.10, 0.10), (0.95, 0.72, 0.30), (0.80, 0.35, 0.15), (0.55, 0.40, 0.75), (0.95, 0.55, 0.65),
    ]
    public static let skinTones: [RGBA] = [(0.99, 0.84, 0.72), (0.95, 0.74, 0.58), (0.80, 0.56, 0.40), (0.58, 0.38, 0.26)]
    public static let shirtColors: [RGBA] = [
        (0.30, 0.55, 0.95), (0.98, 0.55, 0.25), (0.40, 0.75, 0.40), (0.95, 0.45, 0.55),
        (0.62, 0.45, 0.85), (0.98, 0.85, 0.35), (0.35, 0.75, 0.80), (0.95, 0.95, 0.95),
    ]
    /// İlk renkler bugünkü (Blender'da pişirilmiş) pantolon ve ayakkabının sRGB karşılığı; çizici boyamayı sRGB sayar.
    public static let pantsColors: [RGBA] = [
        (0.537, 0.584, 0.702), (0.20, 0.20, 0.22), (0.55, 0.42, 0.30), (0.35, 0.50, 0.38), (0.70, 0.30, 0.30), (0.85, 0.82, 0.75),
    ]
    public static let shoeColors: [RGBA] = [
        (0.773, 0.604, 0.485), (0.15, 0.15, 0.17), (0.95, 0.95, 0.95), (0.90, 0.35, 0.30), (0.30, 0.50, 0.85), (0.95, 0.80, 0.30),
    ]

    /// Oturum kimliğinden sabit görünüş: hash'in ayrı bitleri ayrı özellikleri seçer. Ofis hayatıyla gelen
    /// özellikler bugünkü görünümde kalır (kaydedilmemiş köylüler değişmesin); çeşitlilik "Randomize"dan gelir.
    public static func `default`(for sessionID: String) -> AvatarLook {
        let h = StableHash.mixed(sessionID)
        func pick(_ shift: UInt64, _ count: Int) -> Int { Int((h >> shift) % UInt64(count)) }
        let classic: [HairStyle] = [.short, .pigtails, .spiky, .bob]
        return AvatarLook(hairStyle: classic[pick(0, classic.count)],
                          hairColor: pick(8, hairColors.count), skin: pick(16, skinTones.count),
                          shirtPattern: ShirtPattern.allCases[pick(24, ShirtPattern.allCases.count)],
                          shirtColor: nil, glasses: pick(32, 4) == 0)
    }

    public static func random(using rng: inout some RandomNumberGenerator) -> AvatarLook {
        AvatarLook(hairStyle: HairStyle.allCases.randomElement(using: &rng)!,
                   hairColor: Int.random(in: hairColors.indices, using: &rng),
                   skin: Int.random(in: skinTones.indices, using: &rng),
                   shirtPattern: ShirtPattern.allCases.randomElement(using: &rng)!,
                   shirtColor: Bool.random(using: &rng) ? nil : Int.random(in: shirtColors.indices, using: &rng),
                   glasses: Int.random(in: 0..<4, using: &rng) == 0,
                   hat: Int.random(in: 0..<2, using: &rng) == 0 ? .none : Hat.allCases.randomElement(using: &rng)!,
                   pantsColor: Int.random(in: pantsColors.indices, using: &rng),
                   shoeColor: Int.random(in: shoeColors.indices, using: &rng),
                   eyes: Eyes.allCases.randomElement(using: &rng)!,
                   brows: Brows.allCases.randomElement(using: &rng)!,
                   mouth: Mouth.allCases.randomElement(using: &rng)!,
                   freckles: Int.random(in: 0..<4, using: &rng) == 0,
                   blush: Int.random(in: 0..<4, using: &rng) != 0)
    }

    /// Çizicinin varyant baytları (16): `VillagerVariant` grubu → seçili değer; 0 o gruptan hiçbir şey göstermez.
    public var variantValues: [UInt8] {
        var v = [UInt8](repeating: 0, count: 16)
        let style = UInt8((HairStyle.allCases.firstIndex(of: hairStyle) ?? 0) + 1)
        let hatCode = UInt8(Hat.allCases.firstIndex(of: hat) ?? 0)
        v[VillagerVariant.hair] = style
        v[VillagerVariant.hat] = hatCode
        v[VillagerVariant.eyes] = UInt8((Eyes.allCases.firstIndex(of: eyes) ?? 0) + 1)
        v[VillagerVariant.brows] = UInt8(Brows.allCases.firstIndex(of: brows) ?? 0)
        v[VillagerVariant.mouth] = UInt8((Mouth.allCases.firstIndex(of: mouth) ?? 0) + 1)
        v[VillagerVariant.freckles] = freckles ? 1 : 0
        v[VillagerVariant.blush] = blush ? 1 : 0
        v[VillagerVariant.glasses] = glasses ? 1 : 0
        // Şapka varken saçın tepesi ve tepe süsleri (diken, topuz) gizlenir; yanlar ve kâkül kalır.
        v[VillagerVariant.hairCap] = hat == .none ? 1 : 0
        v[VillagerVariant.hairTop] = hat == .none ? style : 0
        return v
    }
}

/// Köylü mesh'indeki varyant grupları (Blender `VARIANT_GROUPS` ile aynı): köşe (grup, değer) taşır; seçili değer
/// farklıysa gizlenir. Grup 0 her zaman görünür.
public enum VillagerVariant {
    public static let hair = 1, hat = 2, eyes = 3, brows = 4, mouth = 5, freckles = 6, blush = 7, glasses = 8
    public static let hairCap = 9, hairTop = 10
}
