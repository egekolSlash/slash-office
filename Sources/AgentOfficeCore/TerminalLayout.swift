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

    public mutating func cycle() {
        guard let current = focused, let index = visible.firstIndex(of: current), visible.count > 1 else { return }
        focused = visible[(index + 1) % visible.count]
    }

    public var columns: Int { visible.count <= 1 ? 1 : 2 }
    public var rows: Int { visible.count <= 2 ? 1 : 2 }
}
