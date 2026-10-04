import Foundation

public enum ExecutableLocator {
    /// GUI'den açılan uygulamada PATH kısıtlı olabildiği için bilinen dizinler önce denenir.
    public static func defaultDirectories(home: String, pathVariable: String?) -> [String] {
        let known = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin"]
        let fromPath = (pathVariable ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        return (known + fromPath).filter { seen.insert($0).inserted }
    }

    public static func find(_ name: String, searchDirectories: [String], fileManager: FileManager = .default) -> String? {
        searchDirectories
            .map { ($0 as NSString).appendingPathComponent(name) }
            .first { fileManager.isExecutableFile(atPath: $0) }
    }
}
