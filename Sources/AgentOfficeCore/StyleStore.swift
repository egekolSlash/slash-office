import Foundation

/// Kullanıcının değiştirdiği görünüş ve oda stilleri: anahtar → değer, JSON dosyasında.
public enum StyleStore<Value: Codable> {
    public static func load(from url: URL) -> [String: Value] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Value].self, from: data)) ?? [:]
    }

    public static func save(_ values: [String: Value], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(values).write(to: url, options: .atomic)
    }
}
