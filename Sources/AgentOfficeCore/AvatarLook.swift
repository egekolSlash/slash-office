/// Köylünün görünüşü (spec §4). Varsayılanı oturum kimliğinden türer; kullanıcı değiştirebilir.
public struct AvatarLook: Codable, Equatable, Hashable, Sendable {
    public typealias RGBA = (red: Double, green: Double, blue: Double)
    public enum HairStyle: String, Codable, CaseIterable, Sendable { case short, pigtails, spiky, bob }
    public enum ShirtPattern: String, Codable, CaseIterable, Sendable { case plain, stripes, dots }

    public var hairStyle: HairStyle
    public var hairColor: Int
    public var skin: Int
    public var shirtPattern: ShirtPattern
    /// `nil`: projenin rengi.
    public var shirtColor: Int?
    public var glasses: Bool

    public init(hairStyle: HairStyle, hairColor: Int, skin: Int, shirtPattern: ShirtPattern, shirtColor: Int?, glasses: Bool) {
        self.hairStyle = hairStyle; self.hairColor = hairColor; self.skin = skin
        self.shirtPattern = shirtPattern; self.shirtColor = shirtColor; self.glasses = glasses
    }

    public static let hairColors: [RGBA] = [
        (0.30, 0.16, 0.08), (0.12, 0.10, 0.10), (0.95, 0.72, 0.30), (0.80, 0.35, 0.15), (0.55, 0.40, 0.75), (0.95, 0.55, 0.65),
    ]
    public static let skinTones: [RGBA] = [(0.99, 0.84, 0.72), (0.95, 0.74, 0.58), (0.80, 0.56, 0.40), (0.58, 0.38, 0.26)]
    public static let shirtColors: [RGBA] = [
        (0.30, 0.55, 0.95), (0.98, 0.55, 0.25), (0.40, 0.75, 0.40), (0.95, 0.45, 0.55),
        (0.62, 0.45, 0.85), (0.98, 0.85, 0.35), (0.35, 0.75, 0.80), (0.95, 0.95, 0.95),
    ]

    /// Oturum kimliğinden sabit görünüş: hash'in ayrı bitleri ayrı özellikleri seçer.
    public static func `default`(for sessionID: String) -> AvatarLook {
        let h = StableHash.mixed(sessionID)
        func pick(_ shift: UInt64, _ count: Int) -> Int { Int((h >> shift) % UInt64(count)) }
        return AvatarLook(hairStyle: HairStyle.allCases[pick(0, HairStyle.allCases.count)],
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
                   glasses: Int.random(in: 0..<4, using: &rng) == 0)
    }
}
