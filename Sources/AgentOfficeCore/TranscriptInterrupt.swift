import Foundation

/// Esc ile kesilen tur: Claude Code ne `Stop` ne başka bir hook gönderir (soru ya da izin penceresi açıkken de).
/// Kayıt dosyasına ise hemen `[Request interrupted by user]` (araç sırasında `… for tool use]`) yazar. Konuşmanın
/// son kaydı bu ise tur kesilmiştir. Ana thread'de çağrılmamalı.
public enum TranscriptInterrupt {
    static let marker = "[Request interrupted by user"

    public static func endsWithInterrupt(in url: URL, tailBytes: Int = 32_768) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return false }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return false }
        return endsWithInterrupt(lines: String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init))
    }

    /// Sondan ilk kullanıcı ya da asistan kaydı kesinti metni mi (aradaki sistem, başlık, mod kayıtları sayılmaz).
    public static func endsWithInterrupt(lines: [String]) -> Bool {
        for line in lines.reversed() {
            guard line.contains("\"type\":\"user\"") || line.contains("\"type\":\"assistant\""),
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = object["type"] as? String, type == "user" || type == "assistant",
                  object["isSidechain"] as? Bool != true else { continue }
            guard type == "user", let message = object["message"] as? [String: Any] else { return false }
            if let text = message["content"] as? String { return text.hasPrefix(marker) }
            let items = message["content"] as? [[String: Any]] ?? []
            return items.contains { $0["type"] as? String == "text" && ($0["text"] as? String)?.hasPrefix(marker) == true }
        }
        return false
    }
}
