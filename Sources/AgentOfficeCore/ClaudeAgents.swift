import Foundation

/// `claude agents --json` çıktısı: Claude Code'un bildiği etkin oturumlar. Uygulama kapanınca Claude oturumu
/// arka plan servisine geçip çalışmaya devam edebilir; o zaman `--resume` reddedilir, `claude attach` gerekir.
public enum ClaudeAgents {
    public struct Entry: Decodable, Equatable, Sendable {
        /// Kısa kimlik (`claude attach` bunu alır); sadece arka plan oturumlarında olur.
        public var id: String?
        public var sessionId: String
        public var kind: String
        public var cwd: String?

        public init(id: String?, sessionId: String, kind: String, cwd: String? = nil) {
            self.id = id
            self.sessionId = sessionId
            self.kind = kind
            self.cwd = cwd
        }
    }

    /// Bozuk ya da beklenmeyen çıktıda boş liste: devam ettirme her zamanki `--resume` yoluna düşer.
    public static func parse(_ data: Data) -> [Entry] {
        (try? JSONDecoder().decode([Lossy].self, from: data))?.compactMap(\.entry) ?? []
    }

    /// Adaylardan (en yeniden eskiye) arka planda çalışan ilki; `claude attach` için kimliği ve oturum kimliği.
    public static func attachTarget(candidates: [String], agents: [Entry]) -> (attachID: String, sessionID: String)? {
        let background = agents.filter { $0.kind == "background" }
        for candidate in candidates {
            if let entry = background.first(where: { $0.sessionId == candidate }) {
                return (entry.id ?? entry.sessionId, entry.sessionId)
            }
        }
        return nil
    }

    /// Tek bir tanınmayan kayıt bütün listeyi düşürmesin.
    private struct Lossy: Decodable {
        var entry: Entry?
        init(from decoder: Decoder) throws { entry = try? Entry(from: decoder) }
    }
}
