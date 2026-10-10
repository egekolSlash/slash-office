import Foundation
import UniformTypeIdentifiers

/// Dosya türüne göre önizleme kararları.
public enum FileKind {
    /// Uzantısı bir resim türü olan dosya (png, jpg, gif, heic, webp, svg, …).
    public static func isImage(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image)
    }

    /// Terminalde ya da listede görünen yolu oturum klasörüne göre mutlak yola çevirir (`~` açılır,
    /// `dosya.swift:12:4` gibi satır ekleri atılır). Dosya yoksa nil.
    public static func resolve(_ link: String, relativeTo directory: String?,
                               fileManager: FileManager = .default) -> URL? {
        var candidates = [link]
        if let range = link.range(of: #":[0-9]+(?::[0-9]+)?$"#, options: .regularExpression) {
            candidates.append(String(link[..<range.lowerBound]))
        }
        for candidate in candidates {
            let expanded = (candidate as NSString).expandingTildeInPath
            let path: String
            if expanded.hasPrefix("/") {
                path = expanded
            } else if let directory {
                path = (directory as NSString).appendingPathComponent(expanded)
            } else {
                continue
            }
            let standardized = (path as NSString).standardizingPath
            if fileManager.fileExists(atPath: standardized) { return URL(fileURLWithPath: standardized) }
        }
        return nil
    }
}
