import Foundation

/// Mini ofisin kendiliğinden odaklanması: kamera dikkat isteyen masaya döner. Öncelik:
/// soru soran > işi bitip görülmemiş > çalışan; aynı öncelikte kullanıcının panelde açık tutmadığı (bakmadığı)
/// oturum, sonra bu duruma en son giren (bir ajana bakarken başkası çalışmaya başlarsa kamera ona döner).
/// Eşitlikte zaten baktığımız masada kalınır (kamera zıplamasın).
/// Kullanıcı kamerayı elle oynattıysa son jestten 3 sn sonrasına kadar kendiliğinden odak durur.
public enum OfficeAutoFocus {
    public struct Candidate: Equatable, Sendable {
        public var id: String
        public var state: AgentState
        public var unseenFinish: Bool
        public var openInPane: Bool
        /// Bu durum sınıfına ne zaman girdi (`AgentStore.Session.attentionSince`).
        public var since: Date?

        public init(id: String, state: AgentState, unseenFinish: Bool, openInPane: Bool, since: Date?) {
            self.id = id; self.state = state; self.unseenFinish = unseenFinish
            self.openInPane = openInPane; self.since = since
        }
    }

    /// Elle kamera hareketinden (son jestten) sonra kendiliğinden odağın beklediği süre (sn).
    public static let manualPause: TimeInterval = 3

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
        return top.max { a, b in
            let ta = a.since ?? .distantPast, tb = b.since ?? .distantPast
            if ta != tb { return ta < tb }
            if (a.id == current) != (b.id == current) { return b.id == current }
            return a.id > b.id
        }?.id
    }

    /// Seçilen hedef şimdi uygulanmalı mı: elle hareketten sonra beklenir, ama yeni bir soru (bekleyen oturum) bu
    /// beklemeyi aşar (soru dikkat ister).
    public static func shouldApply(target: String?, current: String?, candidates: [Candidate],
                                   lastManualMove: Date?, now: Date) -> Bool {
        guard target != current else { return false }
        guard isPaused(lastManualMove: lastManualMove, now: now) else { return true }
        guard let target, let c = candidates.first(where: { $0.id == target }), case .waiting = c.state else { return false }
        return true
    }

    public static func isPaused(lastManualMove: Date?, now: Date) -> Bool {
        guard let lastManualMove else { return false }
        return now.timeIntervalSince(lastManualMove) < manualPause
    }
}
