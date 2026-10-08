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
        public var pid: Int32?
        /// `working`, `blocked`, `done`...
        public var state: String?
        /// `busy`, `idle`...
        public var status: String?

        public init(id: String?, sessionId: String, kind: String, cwd: String? = nil, pid: Int32? = nil,
                    state: String? = nil, status: String? = nil) {
            self.id = id
            self.sessionId = sessionId
            self.kind = kind
            self.cwd = cwd
            self.pid = pid
            self.state = state
            self.status = status
        }
    }

    /// Listedeki kaba durum; tanınmıyorsa nil (düzeltme yapılmaz).
    public static func state(of entry: Entry) -> AgentState? {
        switch entry.state ?? "" {
        case "working": return .working(tool: nil)
        case "blocked": return .waiting(.permission(""))
        case "done", "idle": return .idle
        default:
            switch entry.status ?? "" {
            case "busy": return .working(tool: nil)
            case "idle": return .idle
            default: return nil
            }
        }
    }

    /// Arka plan oturumunun gösterilen durumu düzeltilmeli mi: listede yoksa kapanmıştır; durum sınıfı farklıysa
    /// listedeki geçerli (kaçan bir hook). Aynı sınıfta hook'un ayrıntısı (tool, soru) korunur: nil.
    public static func correction(current: AgentState, entry: Entry?) -> AgentState? {
        guard let entry else { return current == .exited ? nil : .exited }
        guard let listed = state(of: entry), listed.stateClass != current.stateClass else { return nil }
        return listed
    }

    /// Terminalde önde çalışan `claude` kendi oturumunu yürütmüyor mu (arka plandaki bir oturumu izliyor ya da
    /// ajan görünümünde): süreç, açılışından en az `grace` sn sonra alınmış listede yoksa.
    public static func isViewer(pid: Int32, seenAt: Date, listedAt: Date?, agents: [Entry], grace: TimeInterval = 3) -> Bool {
        guard let listedAt, listedAt.timeIntervalSince(seenAt) >= grace else { return false }
        return !agents.contains { $0.pid == pid }
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
