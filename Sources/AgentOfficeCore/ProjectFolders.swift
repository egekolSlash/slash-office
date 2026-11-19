import Foundation

/// "Proje klasörleri": kullanıcının seçtiği kök klasörlerin (ör. ~/git) altındaki her klasör bir projedir ve proje
/// seçicide son projelerin ardından listelenir. Kök izlenir; yeni proje gelince liste yenilenir.
public enum ProjectFolders {
    /// Kökün doğrudan alt klasörleri, ada göre (doğal sıra). Gizli klasörler ve paketler (.app vb.) atlanır;
    /// klasöre giden sembolik bağlar da sayılır. Kök yoksa boş.
    public static func scan(_ root: String, fileManager: FileManager = .default) -> [String] {
        let rootURL = URL(fileURLWithPath: RecentProjects.normalize(root), isDirectory: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        guard let entries = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: keys,
                                                                 options: [.skipsHiddenFiles]) else { return [] }
        return entries
            .filter { entry in
                let values = try? entry.resolvingSymlinksInPath().resourceValues(forKeys: Set(keys))
                return values?.isDirectory == true && values?.isPackage != true
            }
            .map { rootURL.appendingPathComponent($0.lastPathComponent).path }
            .sorted { ($0 as NSString).lastPathComponent.localizedStandardCompare(($1 as NSString).lastPathComponent) == .orderedAscending }
    }

    /// Bütün köklerden bulunan projeler, tekrarsız (bir kök başka bir kökün altındaysa aynı proje bir kez).
    public static func scan(roots: [String], fileManager: FileManager = .default) -> [String] {
        var seen: Set<String> = []
        return roots.flatMap { scan($0, fileManager: fileManager) }.filter { seen.insert($0).inserted }
    }

    /// Seçicide gösterilen liste: önce son projeler (en yenisi başta), sonra köklerde bulunup son projelerde olmayanlar.
    public static func merged(recent: [String], discovered: [String]) -> [String] {
        let recentSet = Set(recent.map(RecentProjects.normalize))
        return recent + discovered.filter { !recentSet.contains(RecentProjects.normalize($0)) }
    }

    /// Kök listesine ekler: tekrarsız, sona.
    public static func adding(_ root: String, to roots: [String]) -> [String] {
        let normalized = RecentProjects.normalize(root)
        return roots.contains(normalized) ? roots : roots + [normalized]
    }
}
