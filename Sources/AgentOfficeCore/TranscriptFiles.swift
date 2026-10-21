import Foundation

/// Oturumda geçen bir dosya: ajanın değiştirdiği, okuduğu ya da sohbette adı geçen.
public struct SessionFile: Equatable, Sendable, Identifiable {
    public enum Kind: Int, Comparable, Sendable {
        case edited, read, mentioned
        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Mutlak yol.
    public let path: String
    public var kind: Kind
    public var id: String { path }

    public init(path: String, kind: Kind) {
        self.path = path
        self.kind = kind
    }
}

/// Claude Code'un JSONL kaydındaki dosyalar: tool çağrılarının `file_path`'i ve mesajlarda geçen, diskte var olan yollar.
/// En son geçen en başta; bir dosya birden çok şekilde geçtiyse en güçlüsü (değiştirildi > okundu > adı geçti) kalır.
/// Dosya okuyan fonksiyonlar ana thread'de çağrılmamalı.
public enum TranscriptFiles {
    static let editingTools: Set<String> = ["Edit", "MultiEdit", "Write", "NotebookEdit"]

    public static func files(fromLines lines: [Substring], cwd: String, fileManager: FileManager = .default) -> [SessionFile] {
        var order: [String] = []
        var kinds: [String: SessionFile.Kind] = [:]
        var mentionChecks: [String: String?] = [:]
        func note(_ path: String, _ kind: SessionFile.Kind) {
            if let index = order.firstIndex(of: path) { order.remove(at: index) }
            order.append(path)
            kinds[path] = min(kinds[path] ?? kind, kind)
        }
        for line in lines {
            guard line.contains("\"type\":\"user\"") || line.contains("\"type\":\"assistant\""),
                  let record = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)),
                  let type = record["type"]?.string, type == "user" || type == "assistant",
                  record["isMeta"] != .bool(true) else { continue }
            let content = record["message"]?["content"]
            var texts: [String] = []
            if let text = content?.string, type == "user" {
                texts.append(text)
            }
            for block in content?.array ?? [] {
                switch block["type"]?.string {
                case "text":
                    if let text = block["text"]?.string { texts.append(text) }
                case "tool_use":
                    let name = block["name"]?.string ?? ""
                    guard let path = block["input"]?["file_path"]?.string ?? block["input"]?["notebook_path"]?.string,
                          !path.isEmpty else { continue }
                    note(absolute(path, in: cwd), editingTools.contains(name) ? .edited : .read)
                default:
                    continue
                }
            }
            for text in texts where !(type == "user" && TranscriptReader.userText(text) == nil) {
                for token in pathTokens(in: text) {
                    let resolved = mentionChecks[token] ?? {
                        let url = FileKind.resolve(token, relativeTo: cwd, fileManager: fileManager)
                        var isDirectory: ObjCBool = false
                        let path = url.flatMap { fileManager.fileExists(atPath: $0.path, isDirectory: &isDirectory) && !isDirectory.boolValue ? $0.path : nil }
                        mentionChecks[token] = path
                        return path
                    }()
                    if let resolved { note(resolved, .mentioned) }
                }
            }
        }
        return order.reversed().map { SessionFile(path: $0, kind: kinds[$0] ?? .mentioned) }
    }

    /// Kaydın sonundan en çok `tailBytes` okunur; ortadan başlanırsa ilk satır yarımdır, çözülemez ve atlanır.
    public static func read(url: URL, cwd: String, tailBytes: UInt64 = 32 << 20) -> [SessionFile]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: size > tailBytes ? size - tailBytes : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        return files(fromLines: String(decoding: data, as: UTF8.self).split(separator: "\n"), cwd: cwd)
    }

    /// Metindeki yola benzeyen kelimeler: `/` içeren ya da uzantısı olan; web adresleri hariç.
    static func pathTokens(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "`" })
            .map { TerminalLink.clean(String($0)) }
            .filter { token in
                guard token.count > 2, !token.contains("://") else { return false }
                if token.contains("/") { return true }
                let name = token.replacing(/:[0-9]+(:[0-9]+)?$/, with: "")
                let ext = (name as NSString).pathExtension
                return !ext.isEmpty && ext.count <= 10 && ext.first?.isLetter == true && (name as NSString).deletingPathExtension.count > 0
            }
    }

    public static func absolute(_ path: String, in cwd: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let full = expanded.hasPrefix("/") ? expanded : (cwd as NSString).appendingPathComponent(expanded)
        return (full as NSString).standardizingPath
    }
}
