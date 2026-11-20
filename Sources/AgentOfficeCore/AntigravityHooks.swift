import Foundation

/// Antigravity CLI'a (`agy`) oturuma özel hook verilemiyor; hook'lar kullanıcının `~/.gemini/config/hooks.json`
/// dosyasındaki isimli girdilerden gelir ve birleştirilir. Bu dosyaya yalnız kendi girdimizi (`slash-office`) yazarız,
/// diğer girdilere dokunulmaz.
///
/// Girdi Slash Office dışındaki agy oturumlarını etkilemez: yardımcı, oturum değişkeni (`AGENT_OFFICE_SESSION`) yoksa
/// hiçbir şey yapmadan çıkar. agy başarısız olan bir `PreToolUse` hook'unda aracı engeller; bu yüzden komut hiç hata
/// vermez: yardımcı silinmiş ya da taşınmışsa girdiyi okuyup başarıyla çıkar.
public enum AntigravityHooks {
    public static let entryName = "slash-office"

    public static func defaultURL(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".gemini/config/hooks.json")
    }

    public static func command(hookBinaryPath: String) -> String {
        let path = ClaudeLaunch.shellQuote(hookBinaryPath)
        return "if [ -x \(path) ]; then exec \(path) antigravity; else cat >/dev/null; fi"
    }

    /// Girdimiz: oturum başı, tur başı (model çağrısı), araç öncesi / sonrası ve tur sonu.
    public static func entry(hookBinaryPath: String) -> [String: Any] {
        let handler: [String: Any] = ["type": "command", "command": command(hookBinaryPath: hookBinaryPath), "timeout": 5]
        let tools: [[String: Any]] = [["matcher": "*", "hooks": [handler]]]
        return [
            "SessionStart": [handler],
            "PreInvocation": [handler],
            "PreToolUse": tools,
            "PostToolUse": tools,
            "Stop": [handler],
        ]
    }

    public enum InstallError: Error, Equatable {
        /// Dosya var ama JSON nesnesi değil; kullanıcının dosyasını bozmamak için yazılmaz.
        case unreadable
    }

    /// Girdimiz eklenmiş ya da güncellenmiş dosya içeriği; zaten günceldeyse nil.
    public static func merged(existing: Data?, hookBinaryPath: String) throws -> Data? {
        var root: [String: Any] = [:]
        if let existing, !existing.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
            guard let object = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any] else {
                throw InstallError.unreadable
            }
            root = object
        }
        let ours = entry(hookBinaryPath: hookBinaryPath)
        if let current = root[entryName] as? NSDictionary, current.isEqual(to: ours) { return nil }
        root[entryName] = ours
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Girdiyi gerekiyorsa yazar; dosya değiştiyse true.
    @discardableResult
    public static func install(at url: URL, hookBinaryPath: String) throws -> Bool {
        let existing = try? Data(contentsOf: url)
        guard let data = try merged(existing: existing, hookBinaryPath: hookBinaryPath) else { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return true
    }
}
