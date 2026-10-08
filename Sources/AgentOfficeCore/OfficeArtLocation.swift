import Foundation

/// Ofis varlıklarının klasörü: önce uygulama paketi, sonra depo (paketsiz çalışma); yoksa nil (sade görünüm).
public enum OfficeArtLocation {
    public static let marker = "office-art.json"

    public static func find(bundleResources: URL?, repoRoot: URL,
                            fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL? {
        let candidates = [bundleResources?.appendingPathComponent("OfficeArt"),
                          repoRoot.appendingPathComponent("Resources/OfficeArt")].compactMap { $0 }
        return candidates.first { fileExists($0.appendingPathComponent(marker).path) }
    }
}
