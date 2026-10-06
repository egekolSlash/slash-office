import Foundation

/// Claude'un oturuma verdiği başlık (`{"type":"ai-title","aiTitle":…}`): kayıt dosyasının sadece sonu okunur.
/// Ana thread'de çağrılmamalı.
public enum TranscriptTitle {
    public static func latestTitle(in url: URL, tailBytes: Int = 65_536) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        for line in lines.reversed() where line.contains("\"ai-title\"") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["type"] as? String == "ai-title",
                  let title = (object["aiTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { continue }
            return title
        }
        return nil
    }
}
