import CryptoKit
import Foundation

/// İndirilebilir karakter paketleri (ek kıyafetler): uygulamadaki `packs.json` sürüm, adres, SHA-256 ve boyutu sabitler;
/// indirilen zip doğrulanıp `Application Support/AgentOffice/Packs/<kimlik>/` altına açılır. Paket yalnız veridir
/// (`pack.json` + `tex/`), kod içermez.
public struct PackInfo: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var summary: String?
    public var version: String
    public var url: String
    public var sha256: String
    public var bytes: Int

    public init(id: String, title: String, summary: String? = nil, version: String, url: String, sha256: String, bytes: Int) {
        self.id = id; self.title = title; self.summary = summary; self.version = version
        self.url = url; self.sha256 = sha256; self.bytes = bytes
    }
}

public enum PackStore {
    public enum Failure: Error, Equatable {
        case checksum
        case unzip(Int32)
        case missingManifest
    }

    public static let fileName = "packs.json"
    static let marker = "installed.json"

    /// Uygulamanın paketlerinin kökü.
    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentOffice/Packs", isDirectory: true)
    }

    /// Uygulamadaki paket listesi (`Resources/packs.json`); yoksa boş.
    public static func catalog(at url: URL?) -> [PackInfo] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PackInfo].self, from: data)) ?? []
    }

    /// Kurulu paketler: kimlik → (klasör, sürüm), kimlik sırasıyla.
    public static func installed(in root: URL = defaultRoot) -> [(id: String, directory: URL, version: String)] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [] }
        return names.sorted().compactMap { name in
            let dir = root.appendingPathComponent(name, isDirectory: true)
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(marker)),
                  let info = try? JSONDecoder().decode(PackInfo.self, from: data),
                  FileManager.default.fileExists(atPath: dir.appendingPathComponent("pack.json").path) else { return nil }
            return (info.id, dir, info.version)
        }
    }

    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Zip'i doğrular (SHA-256), geçici klasöre açar, `pack.json`'u arar ve kurulu sürümün yerine koyar.
    public static func install(zip: URL, info: PackInfo, root: URL = defaultRoot) throws {
        guard try sha256(of: zip).lowercased() == info.sha256.lowercased() else { throw Failure.checksum }
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".staging-\(info.id)", isDirectory: true)
        try? fm.removeItem(at: staging)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, staging.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { try? fm.removeItem(at: staging); throw Failure.unzip(ditto.terminationStatus) }
        // Zip kökünde ya da tek bir klasörün içinde `pack.json`.
        var content = staging
        if !fm.fileExists(atPath: staging.appendingPathComponent("pack.json").path),
           let inner = try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            .first(where: { fm.fileExists(atPath: $0.appendingPathComponent("pack.json").path) }) {
            content = inner
        }
        guard fm.fileExists(atPath: content.appendingPathComponent("pack.json").path) else {
            try? fm.removeItem(at: staging)
            throw Failure.missingManifest
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(info).write(to: content.appendingPathComponent(marker))
        let destination = root.appendingPathComponent(info.id, isDirectory: true)
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: content, to: destination)
        try? fm.removeItem(at: staging)
    }

    public static func remove(id: String, root: URL = defaultRoot) throws {
        let dir = root.appendingPathComponent(id, isDirectory: true)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
    }

    /// Klasörün diskteki boyutu (bayt).
    public static func size(of directory: URL) -> Int {
        let keys: [URLResourceKey] = [.fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return 0 }
        var total = 0
        for case let url as URL in walker { total += (try? url.resourceValues(forKeys: Set(keys)).fileSize) ?? 0 }
        return total
    }
}
