import Foundation
import Testing

/// Arayüz İngilizce yazılır, Türkçesi `Resources/Localizable.xcstrings`'te (spec: herkese açık sürüm §1).
@Suite struct LocalizationTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let catalog = root.appendingPathComponent("Resources/Localizable.xcstrings")

    static func catalogStrings() throws -> [String: Any] {
        let data = try Data(contentsOf: catalog)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["sourceLanguage"] as? String == "en")
        return try #require(json["strings"] as? [String: Any])
    }

    /// Yeni eklenen her metnin Türkçesi var.
    @Test func everyKeyHasTurkish() throws {
        let strings = try Self.catalogStrings()
        #expect(strings.count > 100)
        var missing: [String] = []
        for (key, value) in strings {
            let entry = value as? [String: Any] ?? [:]
            if entry["shouldTranslate"] as? Bool == false { continue }
            let tr = (entry["localizations"] as? [String: Any])?["tr"] as? [String: Any]
            let unit = tr?["stringUnit"] as? [String: Any]
            if unit?["state"] as? String != "translated" || (unit?["value"] as? String ?? "").isEmpty { missing.append(key) }
        }
        #expect(missing.isEmpty, "Türkçesi eksik: \(missing.sorted())")
    }

    /// Kaynak koddaki dize sabitlerinde Türkçe kalmadı (yorumlar, hata ayıklama günlüğü ve shader kaynağı hariç).
    @Test func noTurkishLeftInSources() throws {
        let turkish = CharacterSet(charactersIn: "çğıöşüÇĞİÖŞÜ")
        var offenders: [String] = []
        for directory in ["Sources/AgentOffice", "Sources/AgentOfficeCore"] {
            let base = Self.root.appendingPathComponent(directory)
            let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
            for file in files where file.lastPathComponent != "OfficeShaders.swift" {
                let source = try String(contentsOf: file, encoding: .utf8)
                for (line, literal) in Self.stringLiterals(in: source) where literal.unicodeScalars.contains(where: turkish.contains) {
                    let text = source.split(separator: "\n", omittingEmptySubsequences: false)[line - 1]
                    if text.contains("DebugLog.write") { continue }
                    offenders.append("\(file.lastPathComponent):\(line): \(literal)")
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders.joined(separator: "\n"))")
    }

    /// SwiftUI ve `String(localized:)` metinlerinin hepsi katalogda (yeni metin eklenip çevrisi unutulmasın).
    @Test func catalogCoversSourceStrings() throws {
        let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")
        let find = Process()
        find.executableURL = xcrun
        find.arguments = ["--find", "xcstringstool"]
        find.standardOutput = FileHandle.nullDevice
        find.standardError = FileHandle.nullDevice
        try find.run()
        find.waitUntilExit()
        guard find.terminationStatus == 0 else { return }  // sadece Command Line Tools: atlanır

        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }
        let sources = FileManager.default.enumerator(at: Self.root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.map(\.path) ?? []
        let extract = Process()
        extract.executableURL = xcrun
        extract.arguments = ["xcstringstool", "extract", "--SwiftUI", "--modern-localizable-strings", "-o", output.path] + sources
        extract.standardOutput = FileHandle.nullDevice
        extract.standardError = FileHandle.nullDevice
        try extract.run()
        extract.waitUntilExit()
        #expect(extract.terminationStatus == 0)

        // Çıkarıcı türleri bilmediği için yer tutucuları `%arg` yazar; çalışma anındaki anahtar `%@`, `%lld`… kullanır.
        func normalized(_ key: String) -> String {
            key.replacingOccurrences(of: #"%(\d+\$)?(@|lld|lf|d|arg)"#, with: "%arg", options: .regularExpression)
        }
        let catalog = Dictionary(try Self.catalogStrings().keys.map { (normalized($0), true) }, uniquingKeysWith: { a, _ in a })
        var missing: Set<String> = []
        for file in try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil) {
            let data = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
            let tables = data?["tables"] as? [String: [[String: Any]]] ?? [:]
            for entry in tables["Localizable"] ?? [] {
                if let key = entry["key"] as? String, catalog[normalized(key)] == nil { missing.insert(key) }
            }
        }
        #expect(missing.isEmpty, "Katalogda yok: \(missing.sorted())")
    }

    /// Basit Swift tarayıcısı: yorumları atlar, dize sabitlerini (satır numarasıyla) döner. `"""` dahil.
    static func stringLiterals(in source: String) -> [(Int, String)] {
        let chars = Array(source)
        var result: [(Int, String)] = []
        var i = 0, line = 1
        func at(_ k: Int) -> Character? { k < chars.count ? chars[k] : nil }
        while i < chars.count {
            let c = chars[i]
            if c == "\n" { line += 1; i += 1; continue }
            if c == "/", at(i + 1) == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", at(i + 1) == "*" {
                i += 2
                while i < chars.count, !(chars[i] == "*" && at(i + 1) == "/") { if chars[i] == "\n" { line += 1 }; i += 1 }
                i += 2
                continue
            }
            if c == "\"" {
                let multi = at(i + 1) == "\"" && at(i + 2) == "\""
                let start = line
                i += multi ? 3 : 1
                var text = ""
                var depth = 0  // \( … ) içindeki parantezler
                while i < chars.count {
                    let d = chars[i]
                    if d == "\\", depth == 0 {
                        if at(i + 1) == "(" { depth = 1; i += 2; continue }
                        text.append(d); if let n = at(i + 1) { text.append(n) }; i += 2; continue
                    }
                    if depth > 0 {
                        if d == "(" { depth += 1 } else if d == ")" { depth -= 1 }
                        i += 1; continue
                    }
                    if d == "\n" { line += 1 }
                    if multi, d == "\"", at(i + 1) == "\"", at(i + 2) == "\"" { i += 3; break }
                    if !multi, d == "\"" { i += 1; break }
                    text.append(d)
                    i += 1
                }
                result.append((start, text))
                continue
            }
            i += 1
        }
        return result
    }
}
