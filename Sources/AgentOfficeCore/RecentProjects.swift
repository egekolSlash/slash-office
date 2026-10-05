import Foundation

/// Son kullanılan proje klasörleri: en yenisi başta, tekrarsız, sınırlı sayıda.
public enum RecentProjects {
    public static let limit = 30

    public static func adding(_ path: String, to list: [String]) -> [String] {
        let normalized = normalize(path)
        return Array(([normalized] + list.filter { $0 != normalized }).prefix(limit))
    }

    /// Ada ya da yola göre filtre; boş sorgu her şeyi döndürür. Ada göre eşleşenler önce gelir.
    public static func filter(_ list: [String], query: String) -> [String] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return list }
        let byName = list.filter { ($0 as NSString).lastPathComponent.lowercased().contains(query) }
        let byPath = list.filter { !byName.contains($0) && $0.lowercased().contains(query) }
        return byName + byPath
    }

    static func normalize(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
