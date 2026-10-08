import Foundation

/// Oda içi yol bulma (v5 spec §5): 0,25 m'lik ızgarada A* (8 komşu, köşe kesmeden), sonra görüş hattıyla
/// sadeleştirme. Masalar, tabureler ve dinlenme köşesinin eşyaları engeldir; duvarlardan pay bırakılır.
/// Tabureler "yumuşak" engeldir: yolun başına ya da sonuna yakınsa geçilir (köylü kendi taburesine oturup kalkar).
public struct RoomNav: Sendable {
    public static let cell = 0.25
    static let body = 0.15
    static let wallMargin = 0.25
    static let softReach = 0.4

    struct Obstacle: Sendable {
        enum Shape: Sendable { case rect(halfX: Double, halfZ: Double), circle(radius: Double) }
        var x: Double, z: Double
        var shape: Shape
        var soft: Bool

        func contains(_ p: PlanPoint, margin: Double = 0) -> Bool {
            switch shape {
            case .rect(let hx, let hz): abs(p.x - x) <= hx + margin && abs(p.z - z) <= hz + margin
            case .circle(let r): hypot(p.x - x, p.z - z) <= r + margin
            }
        }
    }

    let room: OfficePlan.Room
    let obstacles: [Obstacle]
    let nx: Int, nz: Int

    public init(room: OfficePlan.Room) {
        self.room = room
        var obstacles: [Obstacle] = []
        let b = Self.body
        for desk in room.desks {
            // Masa (koridora dönük): koridor ve yan taraflardan gövde payı; tabure tarafında az.
            obstacles.append(Obstacle(x: desk.x, z: desk.z, shape: .rect(halfX: DeskGeometry.deskHalfWidth + 0.05,
                                                                           halfZ: DeskGeometry.deskHalfDepth + b), soft: false))
            let seat = room.seat(for: desk)
            obstacles.append(Obstacle(x: seat.x, z: seat.z, shape: .circle(radius: 0.19 + 0.12), soft: true))
        }
        for spot in room.spots {
            let f = spot.footprint
            if f.round {
                obstacles.append(Obstacle(x: spot.x, z: spot.z, shape: .circle(radius: f.along + b), soft: false))
            } else {
                // Bakış yönü x boyuncaysa (±π/2) "along" x'e düşer.
                let alongX = abs(sin(spot.facing)) > 0.5
                obstacles.append(Obstacle(x: spot.x, z: spot.z,
                                          shape: .rect(halfX: (alongX ? f.along : f.across) + b, halfZ: (alongX ? f.across : f.along) + b),
                                          soft: false))
            }
        }
        self.obstacles = obstacles
        nx = max(1, Int(room.width / Self.cell))
        nz = max(1, Int(room.depth / Self.cell))
    }

    // MARK: - Serbest alan

    func inside(_ p: PlanPoint) -> Bool {
        let m = Self.wallMargin
        if p.distance(to: room.doorInside) < 0.05 { return true }
        return p.x >= room.x + m && p.x <= room.x + room.width - m && p.z >= room.z + m && p.z <= room.z + room.depth - m
    }

    public func isFree(_ p: PlanPoint) -> Bool {
        inside(p) && !obstacles.contains { $0.contains(p) }
    }

    /// Yolun uçlarına yakın yumuşak engeller (tabure) geçilir.
    func isFree(_ p: PlanPoint, near ends: [PlanPoint], margin: Double = 0) -> Bool {
        guard inside(p) else { return false }
        return !obstacles.contains { o in
            o.contains(p, margin: margin) && !(o.soft && ends.contains { $0.distance(to: p) <= Self.softReach })
        }
    }

    func center(_ i: Int, _ j: Int) -> PlanPoint {
        PlanPoint(x: room.x + (Double(i) + 0.5) * Self.cell, z: room.z + (Double(j) + 0.5) * Self.cell)
    }

    func cell(of p: PlanPoint) -> (Int, Int) {
        (min(max(Int((p.x - room.x) / Self.cell), 0), nx - 1), min(max(Int((p.z - room.z) / Self.cell), 0), nz - 1))
    }

    // MARK: - Yol

    public func path(from start: PlanPoint, to target: PlanPoint) -> [PlanPoint]? {
        let ends = [start, target]
        func free(_ i: Int, _ j: Int) -> Bool { isFree(center(i, j), near: ends) }
        // Başlangıç bir mobilyanın içindeyse (ör. koltukta oturan) en yakın boş hücreden çıkılır.
        var s = cell(of: start)
        if !free(s.0, s.1), let near = nearestFree(to: start, free: free) { s = near }
        // Hedef sert bir engelin içindeyse en yakın boş hücreye gidilir.
        let targetFree = isFree(target, near: ends)
        var g = cell(of: target)
        if !free(g.0, g.1) {
            guard let near = nearestFree(to: target, free: free) else { return nil }
            g = near
        }
        guard let cells = astar(from: s, to: g, free: free) else { return nil }
        var points = cells.map { center($0.0, $0.1) }
        points[0] = start
        if targetFree { points[points.count - 1] = target }
        if points.count == 1 { points.append(points[0]) }
        return smooth(points, ends: ends)
    }

    func nearestFree(to p: PlanPoint, free: (Int, Int) -> Bool) -> (Int, Int)? {
        var best: (Int, Int)?, bestD = Double.infinity
        for i in 0..<nx { for j in 0..<nz where free(i, j) {
            let d = center(i, j).distance(to: p)
            if d < bestD { bestD = d; best = (i, j) }
        } }
        return best
    }

    func astar(from s: (Int, Int), to g: (Int, Int), free: (Int, Int) -> Bool) -> [(Int, Int)]? {
        let count = nx * nz
        func id(_ c: (Int, Int)) -> Int { c.1 * nx + c.0 }
        var cost = [Double](repeating: .infinity, count: count)
        var came = [Int](repeating: -1, count: count)
        var closed = [Bool](repeating: false, count: count)
        var open: [(f: Double, id: Int)] = [(0, id(s))]
        cost[id(s)] = 0
        func h(_ i: Int) -> Double { hypot(Double(i % nx - g.0), Double(i / nx - g.1)) }
        while !open.isEmpty {
            // Küçük ızgara: doğrusal arama yeterli.
            let k = open.indices.min { open[$0].f < open[$1].f }!
            let current = open.remove(at: k).id
            if current == id(g) { break }
            if closed[current] { continue }
            closed[current] = true
            let ci = current % nx, cj = current / nx
            for di in -1...1 { for dj in -1...1 where di != 0 || dj != 0 {
                let ni = ci + di, nj = cj + dj
                guard ni >= 0, ni < nx, nj >= 0, nj < nz, free(ni, nj) else { continue }
                // Köşe kesme yok.
                if di != 0 && dj != 0 && (!free(ci + di, cj) || !free(ci, cj + dj)) { continue }
                let n = nj * nx + ni
                let c = cost[current] + (di != 0 && dj != 0 ? 1.4142 : 1)
                if c < cost[n] {
                    cost[n] = c; came[n] = current
                    open.append((c + h(n), n))
                }
            } }
        }
        guard cost[id(g)].isFinite else { return id(s) == id(g) ? [s] : nil }
        var cells: [(Int, Int)] = []
        var c = id(g)
        while c != -1 { cells.append((c % nx, c / nx)); c = came[c] }
        return cells.reversed()
    }

    /// Görüş hattıyla sadeleştirme: her noktadan doğrudan görülebilen en uzak noktaya atla.
    func smooth(_ points: [PlanPoint], ends: [PlanPoint]) -> [PlanPoint] {
        // Köşe sıyırmasın diye kısayollarda küçük bir pay bırakılır.
        func clear(_ a: PlanPoint, _ b: PlanPoint) -> Bool {
            let steps = max(1, Int(a.distance(to: b) / 0.02))
            for k in 0...steps {
                let t = Double(k) / Double(steps)
                let p = PlanPoint(x: a.x + (b.x - a.x) * t, z: a.z + (b.z - a.z) * t)
                if ends.contains(where: { $0.distance(to: p) < 0.05 }) { continue }
                if !isFree(p, near: ends, margin: 0.04) { return false }
            }
            return true
        }
        var out = [points[0]]
        var i = 0
        while i < points.count - 1 {
            var j = points.count - 1
            while j > i + 1 && !clear(points[i], points[j]) { j -= 1 }
            out.append(points[j])
            i = j
        }
        return out
    }
}

extension OfficePlan.Room {
    /// İlgi noktasına yaklaşma: durulacak nokta, bakış yönü ve (koltuksa) oturulacak nokta.
    public func approach(to spot: RoomSpot) -> (stand: PlanPoint, facing: Double, seat: PlanPoint?) {
        let inward = -outward   // dış duvardan koridora doğru
        func toward(_ from: PlanPoint) -> Double { atan2(spot.x - from.x, spot.z - from.z) }
        let ahead = (x: sin(spot.facing), z: cos(spot.facing))
        func front(_ d: Double) -> PlanPoint { PlanPoint(x: spot.x + ahead.x * d, z: spot.z + ahead.z * d) }
        switch spot.kind {
        case .sofa:
            return (front(0.65), spot.facing, front(0.05))
        case .plant:
            let p = PlanPoint(x: spot.x + inward * 0.6, z: spot.z)
            return (p, toward(p), nil)
        case .coffeeTable:
            let p = PlanPoint(x: spot.x + inward * 0.7, z: spot.z)
            return (p, toward(p), nil)
        case .waterCooler, .coffeeMachine:
            let p = front(0.55)
            return (p, toward(p), nil)
        case .bookshelf:
            let p = front(0.55)
            return (p, toward(p), nil)
        case .arcade, .whiteboard:
            let p = front(0.65)
            return (p, toward(p), nil)
        }
    }
}
