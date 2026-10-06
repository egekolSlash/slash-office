/// Terminal alanında hangi oturumların göründüğü ve hangisinin odakta olduğu (spec §4).
public struct TerminalLayout: Equatable, Sendable {
    public static let maxVisible = 4
    public private(set) var visible: [String] = []
    public private(set) var focused: String?

    public init() {}

    /// NPC'ye tıklama: görünürse odakla, değilse odaktaki panelin yerine aç.
    public mutating func show(_ id: String) {
        if visible.contains(id) { focused = id; return }
        if let current = focused, let index = visible.firstIndex(of: current) {
            visible[index] = id
        } else {
            visible.append(id)
        }
        focused = id
    }

    /// ⇧ + tıklama: yanına ekle. Alan doluysa odakta olmayan en eski panel çıkar.
    public mutating func add(_ id: String) {
        if visible.contains(id) { focused = id; return }
        if visible.count >= Self.maxVisible, let index = visible.firstIndex(where: { $0 != focused }) {
            visible.remove(at: index)
        }
        visible.append(id)
        focused = id
    }

    /// Paneli kapatır (oturumu değil). Odak komşu panele geçer.
    public mutating func close(_ id: String) {
        guard let index = visible.firstIndex(of: id) else { return }
        visible.remove(at: index)
        if focused == id {
            focused = visible.isEmpty ? nil : visible[min(index, visible.count - 1)]
        }
    }

    /// Paneldeki oturumu yerinde değiştirir (ör. "yeni" paneli açılan oturuma dönüşür) ve odaklar.
    public mutating func replace(_ old: String, with new: String) {
        guard let index = visible.firstIndex(of: old) else { show(new); return }
        if let existing = visible.firstIndex(of: new), existing != index {
            visible.remove(at: index)
            focused = new
            return
        }
        visible[index] = new
        focused = new
    }

    /// ⌘[ / ⌘]: odaktaki panelde gösterilecek önceki / sonraki oturum. Başka bir panelde zaten açık olanlar atlanır
    /// (odak oraya kaymasın, değişiklik hep odaktaki panelde olsun). Gösterilecek başka oturum yoksa nil.
    public func adjacent(in ids: [String], offset: Int) -> String? {
        let elsewhere = Set(visible.filter { $0 != focused })
        let candidates = ids.filter { !elsewhere.contains($0) }
        guard !candidates.isEmpty else { return nil }
        guard let current = focused, let index = candidates.firstIndex(of: current) else {
            return offset >= 0 ? candidates.first : candidates.last
        }
        let next = candidates[(index + offset % candidates.count + candidates.count) % candidates.count]
        return next == current ? nil : next
    }

    /// ⌘T / ⌘D ile açılan, henüz oturumu olmayan "yeni" paneli.
    public static let launcherPrefix = "launcher-"
    public static func isLauncher(_ id: String) -> Bool { id.hasPrefix(launcherPrefix) }

    public mutating func cycle(backward: Bool = false) {
        guard let current = focused, let index = visible.firstIndex(of: current), visible.count > 1 else { return }
        focused = visible[(index + (backward ? visible.count - 1 : 1)) % visible.count]
    }

    public var columns: Int { visible.count <= 1 ? 1 : 2 }
    public var rows: Int { visible.count <= 2 ? 1 : 2 }
}
