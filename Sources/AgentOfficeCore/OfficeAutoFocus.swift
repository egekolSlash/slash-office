import Foundation

/// Mini ofisin kendiliğinden odaklanması: kamera dikkat isteyen masaya döner. Öncelik:
/// soru soran > işi bitip görülmemiş > çalışan; aynı öncelikte kullanıcının panelde açık tutmadığı (bakmadığı)
/// oturum, sonra en son olayı olan. Zaten baktığımız masa aynı öncelikteyse yerinde kalınır (kamera zıplamasın).
/// Kullanıcı kamerayı elle oynattıysa bir süre kendiliğinden odak durur.
public enum OfficeAutoFocus {
    public struct Candidate: Equatable, Sendable {
        public var id: String
        public var state: AgentState
        public var unseenFinish: Bool
        public var openInPane: Bool
        public var lastEventAt: Date?

        public init(id: String, state: AgentState, unseenFinish: Bool, openInPane: Bool, lastEventAt: Date?) {
            self.id = id; self.state = state; self.unseenFinish = unseenFinish
            self.openInPane = openInPane; self.lastEventAt = lastEventAt
        }
    }

    /// Elle kamera hareketinden sonra kendiliğinden odağın beklediği süre (sn).
    public static let manualPause: TimeInterval = 45

    /// Yüksek daha önemli; nil: odaklanmaya değmez (boşta, başlıyor, çıktı).
    static func score(_ c: Candidate) -> Int? {
        let level: Int
        if case .waiting = c.state { level = 3 }
        else if c.unseenFinish { level = 2 }
        else if case .working = c.state { level = 1 }
        else { return nil }
        return level * 2 + (c.openInPane ? 0 : 1)
    }

    public static func pick(_ candidates: [Candidate], current: String?) -> String? {
        let scored = candidates.compactMap { c in score(c).map { (c, $0) } }
        guard let best = scored.map(\.1).max() else { return nil }
        let top = scored.filter { $0.1 == best }.map(\.0)
        if let current, top.contains(where: { $0.id == current }) { return current }
        return top.max { a, b in
            let ta = a.lastEventAt ?? .distantPast, tb = b.lastEventAt ?? .distantPast
            return ta != tb ? ta < tb : a.id > b.id
        }?.id
    }

    public static func isPaused(lastManualMove: Date?, now: Date) -> Bool {
        guard let lastManualMove else { return false }
        return now.timeIntervalSince(lastManualMove) < manualPause
    }
}
