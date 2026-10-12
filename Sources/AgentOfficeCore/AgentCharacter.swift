import Foundation

/// Oturumdan bağımsız, kalıcı karakter (`characters.json`): isim, rol etiketi, görünüş, kişilik ve imza hareketi.
/// Oturum, odasının kadrosundan bir karakter alır (`CastAssignment`); karakteri düzenlemek onu kullanan bütün
/// oturumlara yansır.
public struct AgentCharacter: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Kısa etiket (ör. "frontend"): isimle birlikte köylünün üstünde ve listede.
    public var role: String?
    public var look: AvatarLook
    public var personality: Personality
    public var signature: Signature

    public init(id: String = UUID().uuidString.lowercased(), name: String, role: String? = nil, look: AvatarLook,
                personality: Personality = Personality(), signature: Signature = Signature()) {
        self.id = id; self.name = name; self.role = role; self.look = look
        self.personality = personality; self.signature = signature
    }

    enum CodingKeys: String, CodingKey { case id, name, role, look, personality, signature }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        role = try c.decodeIfPresent(String.self, forKey: .role).flatMap(AvatarLook.trimmedName)
        look = try c.decode(AvatarLook.self, forKey: .look)
        personality = try c.decodeIfPresent(Personality.self, forKey: .personality) ?? Personality()
        signature = try c.decodeIfPresent(Signature.self, forKey: .signature) ?? Signature()
    }

    /// Köylünün üstündeki etiket: "İsim · rol".
    public var label: String { role.map { "\(name) · \($0)" } ?? name }
}

/// Boştayken ne yapmayı sever, ne hızda yürür.
public struct Personality: Codable, Equatable, Hashable, Sendable {
    public enum Pace: String, Codable, CaseIterable, Sendable {
        case slow, normal, brisk
        public var scale: Double {
            switch self {
            case .slow: 0.8
            case .normal: 1
            case .brisk: 1.2
            }
        }
    }

    /// Eşya → istek (0 hiç gitmez, 1 normal, 2–3 daha sık). Kaydı olmayan eşya 1.
    public var favorites: [RoomSpot.Kind: Int]
    public var pace: Pace

    public init(favorites: [RoomSpot.Kind: Int] = [:], pace: Pace = .normal) {
        self.favorites = favorites; self.pace = pace
    }

    public static let maxWeight = 3

    public func weight(_ kind: RoomSpot.Kind) -> Int { min(Self.maxWeight, max(0, favorites[kind] ?? 1)) }

    enum CodingKeys: String, CodingKey { case favorites, pace }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Tanınmayan eşya adları atlanır.
        let raw = try c.decodeIfPresent([String: Int].self, forKey: .favorites) ?? [:]
        favorites = raw.reduce(into: [:]) { result, item in
            if let kind = RoomSpot.Kind(rawValue: item.key) { result[kind] = item.value }
        }
        pace = try c.decodeIfPresent(Pace.self, forKey: .pace) ?? .normal
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Dictionary(uniqueKeysWithValues: favorites.map { ($0.key.rawValue, $0.value) }), forKey: .favorites)
        try c.encode(pace, forKey: .pace)
    }
}

/// Karakterin kendine özgü hareketi ve yüzü: iş bitince sevinç hareketi; dinlenirken göz ve ağız.
public struct Signature: Codable, Equatable, Hashable, Sendable {
    public enum Celebration: String, Codable, CaseIterable, Sendable {
        case cheer, bow, peace
        public var clip: AvatarClip {
            switch self {
            case .cheer: .cheer
            case .bow: .bow
            case .peace: .peace
            }
        }
    }

    public var celebration: Celebration
    /// nil: görünüşün kendi gözü / ağzı.
    public var restingMouth: AvatarLook.Mouth?

    public init(celebration: Celebration = .cheer, restingMouth: AvatarLook.Mouth? = nil) {
        self.celebration = celebration; self.restingMouth = restingMouth
    }

    enum CodingKeys: String, CodingKey { case celebration, restingMouth }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        celebration = (try? c.decodeIfPresent(Celebration.self, forKey: .celebration)) ?? .cheer
        restingMouth = try? c.decodeIfPresent(AvatarLook.Mouth.self, forKey: .restingMouth)
    }
}

/// Odanın kaydı (`rooms.json`, anahtar proje kökü): isim, stil ve kadro. Eski kayıtlar doğrudan `RoomStyle`'dı.
public struct RoomRecord: Codable, Equatable, Sendable {
    public var name: String?
    /// nil: oda anahtarından türeyen varsayılan stil.
    public var style: RoomStyle?
    /// Sıralı karakter kimlikleri: oturumlar boştaki ilkini alır.
    public var cast: [String]

    public init(name: String? = nil, style: RoomStyle? = nil, cast: [String] = []) {
        self.name = name; self.style = style; self.cast = cast
    }

    public var isEmpty: Bool { name == nil && style == nil && cast.isEmpty }

    enum CodingKeys: String, CodingKey { case name, style, cast, wallpaper }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.wallpaper) {
            // Eski biçim: değer doğrudan oda stili.
            self.init(style: try RoomStyle(from: decoder))
        } else {
            self.init(name: try c.decodeIfPresent(String.self, forKey: .name).flatMap(AvatarLook.trimmedName),
                      style: try c.decodeIfPresent(RoomStyle.self, forKey: .style),
                      cast: try c.decodeIfPresent([String].self, forKey: .cast) ?? [])
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(style, forKey: .style)
        try c.encode(cast, forKey: .cast)
    }
}

/// Oturumlara kadrodan karakter atama. Elle seçilmiş (ya da önceden atanmış) karakter kalır; diğerleri odasının
/// kadrosunda o odada boşta olan ilk karakteri alır (oturumlar açılış sırasıyla). Kadro yoksa ya da yetmezse oturum
/// karaktersiz kalır (görünüşü kimliğinden türer, eskisi gibi).
public enum CastAssignment {
    public struct Seat: Equatable, Sendable {
        public var id: String
        public var roomKey: String
        /// Kayıtlı seçim: karakter kimliği, `random` ya da nil (otomatik).
        public var choice: String?
        public init(id: String, roomKey: String, choice: String?) { self.id = id; self.roomKey = roomKey; self.choice = choice }
    }

    /// Kullanıcı "rastgele" seçtiyse kadrodan karakter verilmez.
    public static let random = "random"

    /// Oturum → karakter (karaktersizler yok). `seats` açılış sırasıyla; yalnız var olan karakterler atanır.
    public static func assign(_ seats: [Seat], rooms: [String: RoomRecord], characters: Set<String>) -> [String: String] {
        var result: [String: String] = [:]
        var used: [String: Set<String>] = [:]
        for seat in seats {
            if let choice = seat.choice, choice != random, characters.contains(choice) {
                result[seat.id] = choice
                used[seat.roomKey, default: []].insert(choice)
            }
        }
        for seat in seats where seat.choice == nil || (seat.choice != random && !characters.contains(seat.choice!)) {
            let cast = rooms[seat.roomKey]?.cast ?? []
            guard let free = cast.first(where: { characters.contains($0) && !used[seat.roomKey, default: []].contains($0) }) else { continue }
            result[seat.id] = free
            used[seat.roomKey, default: []].insert(free)
        }
        return result
    }
}

/// İlk açılışta eski oturum görünüşleri (`avatars.json`) karaktere dönüşür: isim (yoksa oturum başlığı), görünüş;
/// oturum o karaktere bağlanır ve odasının kadrosuna eklenir.
public enum CharacterMigration {
    public struct Result: Equatable, Sendable {
        public var characters: [AgentCharacter]
        /// Oturum → karakter kimliği.
        public var choices: [String: String]
        public var rooms: [String: RoomRecord]
    }

    public static func migrate(looks: [String: AvatarLook], titles: [String: String], roomKeys: [String: String],
                               rooms: [String: RoomRecord]) -> Result {
        var characters: [AgentCharacter] = []
        var choices: [String: String] = [:]
        var rooms = rooms
        for id in looks.keys.sorted() {
            guard let look = looks[id] else { continue }
            var cleaned = look
            cleaned.name = nil
            let character = AgentCharacter(id: "migrated-" + id, name: look.name ?? titles[id] ?? "Agent", look: cleaned)
            characters.append(character)
            choices[id] = character.id
            if let key = roomKeys[id] {
                var room = rooms[key] ?? RoomRecord()
                if !room.cast.contains(character.id) { room.cast.append(character.id) }
                rooms[key] = room
            }
        }
        return Result(characters: characters, choices: choices, rooms: rooms)
    }
}

/// `characters.json`: sıralı karakter listesi.
public enum CharacterFile {
    public static func load(from url: URL) -> [AgentCharacter] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([AgentCharacter].self, from: data)) ?? []
    }

    public static func save(_ characters: [AgentCharacter], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(characters).write(to: url, options: .atomic)
    }
}
