import Foundation

public enum SessionKind: String, Codable, Sendable {
    case claude, shell
}

/// Uygulama yeniden açıldığında oturumu geri getirmek için gereken kalıcı bilgi.
public struct SessionRecord: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var cwd: String
    /// Claude'un son bildirdiği oturum kimliği (`/clear` sonrası değişir). `--resume` bununla yapılır.
    public var claudeSessionID: String?
    /// Önceki Claude oturum kimlikleri, en yenisi başta.
    public var claudeSessionHistory: [String] = []
    public var createdAt: Date
    public var kind: SessionKind = .claude
    /// Oturum açıldığında klasörün `HEAD`'i; diff bunun üzerinden alınır. Git deposu değilse nil.
    public var baseline: String?

    public init(id: String, title: String, cwd: String, claudeSessionID: String?, createdAt: Date, kind: SessionKind = .claude) {
        self.id = id
        self.title = title
        self.cwd = cwd
        self.claudeSessionID = claudeSessionID
        self.createdAt = createdAt
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        cwd = try container.decode(String.self, forKey: .cwd)
        claudeSessionID = try container.decodeIfPresent(String.self, forKey: .claudeSessionID)
        claudeSessionHistory = try container.decodeIfPresent([String].self, forKey: .claudeSessionHistory) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // Tür alanından önceki kayıtlar Claude oturumudur.
        kind = try container.decodeIfPresent(SessionKind.self, forKey: .kind) ?? .claude
        baseline = try container.decodeIfPresent(String.self, forKey: .baseline)
    }
}

public enum SessionStore {
    /// Dosya yoksa ya da bozuksa boş liste döner; uygulama açılışı hiçbir zaman buna takılmaz.
    public static func load(from url: URL) -> [SessionRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        if let records = try? decoder.decode([SessionRecord].self, from: data) { return records }
        // Bozuk dosyayı kenara al ki bir sonraki kayıt onu ezmesin; elle kurtarılabilsin.
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = url.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: aside)
        return []
    }

    public static func save(_ records: [SessionRecord], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(records).write(to: url, options: .atomic)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum ClaudeTranscript {
    /// Claude bir oturumun transcript'ini ancak ilk mesajdan sonra yazar; transcript yoksa `--resume` başarısız olur.
    public static func exists(sessionID: String, projectsDirectory: URL, fileManager: FileManager = .default) -> Bool {
        guard let projects = try? fileManager.contentsOfDirectory(atPath: projectsDirectory.path) else { return false }
        return projects.contains { project in
            fileManager.fileExists(atPath: projectsDirectory.appendingPathComponent(project).appendingPathComponent("\(sessionID).jsonl").path)
        }
    }
}
