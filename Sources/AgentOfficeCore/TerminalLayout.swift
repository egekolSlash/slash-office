/// Panel düzeninde bir bölme: `horizontal` yan yana (ilk sol), `vertical` üst üste (ilk üst). Bölmeler eşit.
public enum PaneAxis: Equatable, Sendable { case horizontal, vertical }

/// Bir panelin üstüne bırakılan oturumun yeri: kenarlar paneli o yönden böler, orta paneli değiştirir.
public enum PaneEdge: Equatable, Sendable { case left, right, top, bottom, center }

public indirect enum PaneNode: Equatable, Sendable {
    case leaf(String)
    case split(PaneAxis, PaneNode, PaneNode)

    public var leaves: [String] {
        switch self {
        case .leaf(let id): [id]
        case .split(_, let a, let b): a.leaves + b.leaves
        }
    }

    func replacing(_ id: String, with node: PaneNode) -> PaneNode {
        switch self {
        case .leaf(let leaf): leaf == id ? node : self
        case .split(let axis, let a, let b): .split(axis, a.replacing(id, with: node), b.replacing(id, with: node))
        }
    }

    /// Yaprağı çıkarır; kardeşi ebeveynin yerine geçer. Ağaç boşalırsa nil.
    func removing(_ id: String) -> PaneNode? {
        switch self {
        case .leaf(let leaf): return leaf == id ? nil : self
        case .split(let axis, let a, let b):
            switch (a.removing(id), b.removing(id)) {
            case (let a?, let b?): return .split(axis, a, b)
            case (let a?, nil): return a
            case (nil, let b?): return b
            case (nil, nil): return nil
            }
        }
    }

    /// Yaprakların birim alandaki boyutları (genişlik, yükseklik), ağaç sırasıyla.
    func sizes(width: Double, height: Double) -> [(id: String, width: Double, height: Double)] {
        switch self {
        case .leaf(let id): return [(id, width, height)]
        case .split(.horizontal, let a, let b):
            return a.sizes(width: width / 2, height: height) + b.sizes(width: width / 2, height: height)
        case .split(.vertical, let a, let b):
            return a.sizes(width: width, height: height / 2) + b.sizes(width: width, height: height / 2)
        }
    }
}

/// Terminal alanında hangi oturumların göründüğü, nasıl bölündüğü ve hangisinin odakta olduğu (spec §4).
/// `root` bölme ağacıdır; `visible` panellerin açılış sırası (⇧ ile eklemede en eski, ⌃⇥ ile gezinme sırası).
public struct TerminalLayout: Equatable, Sendable {
    public static let maxVisible = 4
    public private(set) var visible: [String] = []
    public private(set) var focused: String?
    public private(set) var root: PaneNode?

    public init() {}

    /// NPC'ye tıklama: görünürse odakla, değilse odaktaki panelin yerine aç.
    public mutating func show(_ id: String) {
        if visible.contains(id) { focused = id; return }
        if let current = focused, visible.contains(current) {
            rename(current, to: id)
        } else {
            insertBesideLargest(id)
        }
        focused = id
    }

    /// ⇧ + tıklama: yanına ekle (en büyük panel uzun kenarından bölünür; 2 yan yana, 3–4 2×2). Alan doluysa
    /// odakta olmayan en eski panel çıkar.
    public mutating func add(_ id: String) {
        if visible.contains(id) { focused = id; return }
        if visible.count >= Self.maxVisible, let oldest = visible.first(where: { $0 != focused }) {
            detach(oldest)
        }
        insertBesideLargest(id)
        focused = id
    }

    /// Paneli kapatır (oturumu değil). Odak komşu panele geçer.
    public mutating func close(_ id: String) {
        guard let index = visible.firstIndex(of: id) else { return }
        detach(id)
        if focused == id {
            focused = visible.isEmpty ? nil : visible[min(index, visible.count - 1)]
        }
    }

    /// Paneldeki oturumu yerinde değiştirir (ör. "yeni" paneli açılan oturuma dönüşür) ve odaklar.
    public mutating func replace(_ old: String, with new: String) {
        guard visible.contains(old) else { show(new); return }
        if visible.contains(new), new != old {
            detach(old)
            focused = new
            return
        }
        rename(old, to: new)
        focused = new
    }

    /// Sürükle-bırak: `id` (listeden bir oturum ya da başka bir panel) `target` panelinin `edge` kenarına.
    /// Kenar paneli o yönden böler; orta, yeni oturumda paneli değiştirir, var olan panelde ikisini yer değiştirir.
    public mutating func drop(_ id: String, on target: String, edge: PaneEdge) {
        guard visible.contains(target) else { return }
        guard id != target else { focused = id; return }
        switch dropEdge(for: id, on: target, edge: edge) {
        case .center:
            if visible.contains(id) { swap(id, target) } else { rename(target, to: id) }
        case let side:
            if visible.contains(id) { detach(id) }
            let axis: PaneAxis = side == .left || side == .right ? .horizontal : .vertical
            let before = side == .left || side == .top
            root = root?.replacing(target, with: before ? .split(axis, .leaf(id), .leaf(target))
                                                        : .split(axis, .leaf(target), .leaf(id)))
            let index = visible.firstIndex(of: target)!
            visible.insert(id, at: before ? index : index + 1)
        }
        focused = id
    }

    /// Bırakmanın gerçekte nereye olacağı: alan doluyken yeni bir oturum kenara değil, panelin yerine gelir.
    public func dropEdge(for id: String, on target: String, edge: PaneEdge) -> PaneEdge {
        if id == target { return .center }
        if edge != .center, !visible.contains(id), visible.count >= Self.maxVisible { return .center }
        return edge
    }

    /// Panel içindeki bir noktanın bırakma bölgesi: kenara en yakın çeyrekte o kenar, ortada `center`.
    public static func edge(x: Double, y: Double, width: Double, height: Double) -> PaneEdge {
        guard width > 0, height > 0 else { return .center }
        let distances: [(PaneEdge, Double)] = [(.left, x / width), (.right, 1 - x / width),
                                               (.top, y / height), (.bottom, 1 - y / height)]
        let nearest = distances.min { $0.1 < $1.1 }!
        return nearest.1 < 0.25 ? nearest.0 : .center
    }

    /// En büyük paneli uzun kenarından böler (alan pencere gibi geniş varsayılır); boşsa ilk panel.
    private mutating func insertBesideLargest(_ id: String) {
        visible.append(id)
        guard let root else { self.root = .leaf(id); return }
        let sizes = root.sizes(width: 1.6, height: 1)
        let largest = sizes.reduce(sizes[0]) { best, next in
            next.width * next.height > best.width * best.height + 1e-9 ? next : best
        }
        let axis: PaneAxis = largest.width >= largest.height ? .horizontal : .vertical
        self.root = root.replacing(largest.id, with: .split(axis, .leaf(largest.id), .leaf(id)))
    }

    private mutating func detach(_ id: String) {
        visible.removeAll { $0 == id }
        root = root?.removing(id)
    }

    private mutating func rename(_ old: String, to new: String) {
        if let index = visible.firstIndex(of: old) { visible[index] = new }
        root = root?.replacing(old, with: .leaf(new))
    }

    private mutating func swap(_ a: String, _ b: String) {
        let marker = "\u{0}swap"
        rename(a, to: marker)
        rename(b, to: a)
        rename(marker, to: b)
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
}
