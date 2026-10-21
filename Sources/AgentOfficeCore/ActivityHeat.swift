import Foundation

/// Bir oturumun son bir saatte ne kadar çalıştığı ve kaç istek aldığı. Pencereden eski kayıtlar atılır.
public struct ActivityLog: Equatable, Sendable {
    public static let window: TimeInterval = 3600

    /// Biten çalışma aralıkları; süren çalışma `busySince`'ten beri.
    public private(set) var spans: [DateInterval] = []
    public private(set) var busySince: Date?
    public private(set) var prompts: [Date] = []

    public init() {}

    public mutating func note(busy: Bool, at date: Date) {
        if busy, busySince == nil {
            busySince = date
        } else if !busy, let start = busySince {
            spans.append(DateInterval(start: start, end: max(start, date)))
            busySince = nil
        }
        prune(now: date)
    }

    public mutating func notePrompt(at date: Date) {
        prompts.append(date)
        prune(now: date)
    }

    /// Pencere içinde çalışarak geçen süre.
    public func busySeconds(now: Date) -> TimeInterval {
        let from = now.addingTimeInterval(-Self.window)
        var total = spans.reduce(0) { $0 + max(0, $1.end.timeIntervalSince(max($1.start, from))) }
        if let busySince { total += max(0, now.timeIntervalSince(max(busySince, from))) }
        return min(total, Self.window)
    }

    public func promptCount(now: Date) -> Int {
        let from = now.addingTimeInterval(-Self.window)
        return prompts.count { $0 > from }
    }

    private mutating func prune(now: Date) {
        let from = now.addingTimeInterval(-Self.window)
        spans.removeAll { $0.end < from }
        prompts.removeAll { $0 < from }
    }
}

/// Oturum listesindeki aktiflik şeridi: oturumlar birbirine göre sıralanır, en az boşta kalan 1, en çok boşta kalan 0.
/// Puanın çoğu çalışma süresinden, kalanı istek sayısından gelir (ikisi de en yüksek olana bölünür).
public enum ActivityHeat {
    public static func levels(_ logs: [String: ActivityLog], now: Date) -> [String: Double] {
        let busy = logs.mapValues { $0.busySeconds(now: now) }
        let prompts = logs.mapValues { Double($0.promptCount(now: now)) }
        let maxBusy = busy.values.max() ?? 0, maxPrompts = prompts.values.max() ?? 0
        let scores = logs.keys.reduce(into: [String: Double]()) { scores, id in
            let busyShare = maxBusy > 0 ? busy[id, default: 0] / maxBusy : 0
            let promptShare = maxPrompts > 0 ? prompts[id, default: 0] / maxPrompts : 0
            scores[id] = 0.7 * busyShare + 0.3 * promptShare
        }
        guard let low = scores.values.min(), let high = scores.values.max() else { return [:] }
        // Hepsi eşitse sıralama yok: hiç iş yoksa hepsi soğuk, varsa hepsi sıcak.
        guard high > low else { return scores.mapValues { $0 > 0 ? 1 : 0 } }
        return scores.mapValues { ($0 - low) / (high - low) }
    }
}
