import Foundation

/// Sağ sütundaki oturum listesinin sıralaması. `manual` kullanıcının sürükleyerek verdiği sıradır; diğerleri
/// her an yeniden hesaplanır ve eşitlikte elle verilen sıraya düşer.
public enum SessionSort: String, CaseIterable, Identifiable, Sendable {
    case manual, activity, recent, project, name, status

    public var id: String { rawValue }
}

public enum SessionOrder {
    public struct Item: Equatable, Sendable {
        public var id: String
        public var name: String
        /// Projenin adı (worktree'ler ana deponun adıyla aynı grupta).
        public var project: String
        public var state: AgentState
        /// Son hook olayı ya da durum değişimi; yeniden açılışta nil.
        public var lastActive: Date?
        /// Son bir saatteki aktiflik puanı (0...1, `ActivityHeat`).
        public var heat: Double

        public init(id: String, name: String, project: String, state: AgentState, lastActive: Date?, heat: Double) {
            self.id = id
            self.name = name
            self.project = project
            self.state = state
            self.lastActive = lastActive
            self.heat = heat
        }
    }

    /// `items` elle verilen sırayla gelir; dönen kimlikler listede gösterilecek sıradır.
    public static func sorted(_ items: [Item], by sort: SessionSort) -> [String] {
        let manual = Dictionary(items.enumerated().map { ($1.id, $0) }) { first, _ in first }
        func before(_ a: Item, _ b: Item) -> Bool {
            switch compare(a, b, sort) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: manual[a.id, default: 0] < manual[b.id, default: 0]
            }
        }
        return items.sorted(by: before).map(\.id)
    }

    private static func compare(_ a: Item, _ b: Item, _ sort: SessionSort) -> ComparisonResult {
        switch sort {
        case .manual:
            return .orderedSame
        case .activity:
            if a.heat != b.heat { return a.heat > b.heat ? .orderedAscending : .orderedDescending }
            return recency(a, b)
        case .recent:
            return recency(a, b)
        case .project:
            let project = a.project.localizedStandardCompare(b.project)
            return project != .orderedSame ? project : a.name.localizedStandardCompare(b.name)
        case .name:
            let name = a.name.localizedStandardCompare(b.name)
            return name != .orderedSame ? name : a.project.localizedStandardCompare(b.project)
        case .status:
            let (ra, rb) = (urgency(a.state), urgency(b.state))
            return ra == rb ? recency(a, b) : (ra < rb ? .orderedAscending : .orderedDescending)
        }
    }

    /// En yeni önce; hiç olay almamış oturumlar sonda.
    private static func recency(_ a: Item, _ b: Item) -> ComparisonResult {
        switch (a.lastActive, b.lastActive) {
        case let (x?, y?) where x != y: x > y ? .orderedAscending : .orderedDescending
        case (_?, nil): .orderedAscending
        case (nil, _?): .orderedDescending
        default: .orderedSame
        }
    }

    /// Durum sıralamasında önce ilgi bekleyenler: cevap bekleyen, çalışan, açılan, boşta, durmuş.
    private static func urgency(_ state: AgentState) -> Int {
        switch state.stateClass {
        case 3: 0 // bekliyor
        case 2: 1 // çalışıyor
        case 0: 2 // açılıyor
        case 1: 3 // boşta
        default: 4 // durmuş
        }
    }

    /// Gösterilen sırada `from` satırları `to` konumuna taşınınca oluşan yeni elle sıra (`List.onMove` ile aynı anlam).
    public static func moving(_ ids: [String], from offsets: IndexSet, to destination: Int) -> [String] {
        let moved = offsets.filter { ids.indices.contains($0) }.map { ids[$0] }
        var rest = ids.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertAt = destination - offsets.count { $0 < destination }
        rest.insert(contentsOf: moved, at: min(max(insertAt, 0), rest.count))
        return rest
    }
}
