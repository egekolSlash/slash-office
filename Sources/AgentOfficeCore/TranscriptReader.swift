import Foundation

/// Claude Code'un JSONL kaydından telefonda gösterilecek sohbet (spec §5): ana konuşma, tool çağrıları tek satır.
/// Dosya okuyan fonksiyonlar ana thread'de çağrılmamalı.
public enum TranscriptReader {
    public static func messages(fromLines lines: [Substring]) -> [RemoteMessage] {
        lines.flatMap(messages(fromLine:))
    }

    static func messages(fromLine line: Substring) -> [RemoteMessage] {
        guard line.contains("\"type\":\"user\"") || line.contains("\"type\":\"assistant\""),
              let record = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)),
              let type = record["type"]?.string, type == "user" || type == "assistant",
              record["isSidechain"] != .bool(true), record["isMeta"] != .bool(true),
              let uuid = record["uuid"]?.string else { return [] }
        let time = record["timestamp"]?.string
        let content = record["message"]?["content"]
        if let text = content?.string {
            guard type == "user", let text = userText(text) else { return [] }
            return [RemoteMessage(id: "\(uuid):0", role: .user, text: text, time: time)]
        }
        return (content?.array ?? []).enumerated().compactMap { (index, block) -> RemoteMessage? in
            let id = "\(uuid):\(index)"
            switch (type, block["type"]?.string) {
            case ("user", "text"):
                return block["text"]?.string.flatMap(userText).map { RemoteMessage(id: id, role: .user, text: $0, time: time) }
            case ("assistant", "text"):
                guard let text = block["text"]?.string, !text.isEmpty else { return nil }
                return RemoteMessage(id: id, role: .assistant, text: text, time: time)
            case ("assistant", "tool_use"):
                let name = block["name"]?.string ?? "?"
                let summary = ClaudeNormalizer.summary(of: block["input"])
                return RemoteMessage(id: id, role: .tool, text: summary.map { "\(name) \($0)" } ?? name, time: time)
            default:
                return nil
            }
        }
    }

    /// Komut ve sistem etiketleri (`<command-name>…`, `<local-command-stdout>…`) sohbet değil.
    static func userText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasPrefix("<") ? nil : trimmed
    }

    /// `offset`'ten itibaren tamamlanmış satırları okur; yarım kalan son satır bir sonraki okumaya kalır.
    /// `maxBytes` içinde hiç satır sonu yoksa (dev bir satır) o kısım atlanır, okuma takılı kalmaz.
    public static func read(url: URL, from offset: UInt64, maxBytes: Int = 16 << 20) -> TranscriptPage? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        guard offset < size else { return TranscriptPage(messages: [], cursor: size) }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.read(upToCount: maxBytes), !data.isEmpty else { return nil }
        guard let newline = data.lastIndex(of: 0x0A) else {
            // Pencere doluysa ve dosyada daha fazlası varsa dev satırdır; aksi halde yazılmakta olan satırdır, beklenir.
            let skipped = data.count >= maxBytes && offset + UInt64(data.count) < size ? UInt64(data.count) : 0
            return TranscriptPage(messages: [], cursor: offset + skipped)
        }
        let complete = data[data.startIndex...newline]
        let lines = String(decoding: complete, as: UTF8.self).split(separator: "\n")
        return TranscriptPage(messages: messages(fromLines: lines), cursor: offset + UInt64(complete.count))
    }

    /// İlk açılış: dosyanın sonundan en çok `maxMessages` mesaj. Ortadan başlanırsa ilk satır yarımdır ve
    /// JSON olarak çözülemediği için kendiliğinden atlanır.
    public static func tail(url: URL, maxMessages: Int = 200, tailBytes: UInt64 = 2 << 20) -> TranscriptPage? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else { return nil }
        let start = size > tailBytes ? size - tailBytes : 0
        guard size > 0 else { return TranscriptPage(messages: [], cursor: 0) }
        guard var page = read(url: url, from: start, maxBytes: Int(size - start)) else { return nil }
        page.messages = Array(page.messages.suffix(maxMessages))
        return page
    }
}
