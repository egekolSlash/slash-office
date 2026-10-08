import Foundation

/// Köylünün gideceği yer ve orada oynayacağı döngü.
public enum AvatarGoal: Equatable, Sendable {
    /// Masada, taburede otur (sitType ya da sitDoze).
    case seat(loop: AvatarClip)
    /// Masanın yanında ayakta dur (wave; iş bitince sevinmek için idle).
    case stand(loop: AvatarClip)
    /// Dinlenme köşesindeki bir noktaya git: varınca tek seferlik hareket (varsa), sonra döngü; `dwell` sn kal.
    case spot(RoomSpot.Kind, loop: AvatarClip?, oneShot: AvatarClip?, dwell: Double)
    /// Kapıdan çık.
    case leave
}

/// Köylünün davranışı (v5 spec §5): sabit tohumlu, kendi saatiyle karar veren durum makinesi. Ne yapacağına karar
/// verir; yürüme, klipler ve rezervasyon `AvatarSim`'dedir.
/// - Çalışıyor: masada `sitType`; 8–20 sn'de bir `sitSip` / `sitThink` / `sitStretch`.
/// - Bekliyor: masanın yanında `wave`; 2–3 el sallamada bir `waitTap` / `lookAround`.
/// - Boşta: masada `sitDoze`; 20–60 sn sonra boş bir ilgi noktasına gider, sonra başka bir noktaya ya da masaya döner.
/// - İş bitince (görülmemiş): bir kez ayağa kalkıp `cheer`, sonra boşta kuralları.
/// - Çıktı: kapıdan çıkar.
public struct AvatarBehavior: Sendable {
    public enum Decision: Equatable, Sendable {
        case goal(AvatarGoal)
        case oneShot(AvatarClip)
    }

    private var rng: SeededRandom
    private var activity: AvatarActivity?
    private var needGoal = false
    private var pendingCheer = false
    private var queued: (clip: AvatarClip, after: Double)?
    private var timer = 0.0
    private var atSpot: RoomSpot.Kind?
    /// Masasında oturuyor mu (boşta: gidecek yer yoksa masaya döner).
    private var atDesk = false
    /// Noktaya gidilirken: varınca başlayacak kalma süresi.
    private var pendingDwell: Double?

    public init(id: String) {
        rng = SeededRandom(seed: StableHash.mixed("behavior:" + id))
    }

    private mutating func random(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + rng.next() * (range.upperBound - range.lowerBound)
    }

    private mutating func pick<T>(_ items: [T]) -> T {
        items[Int(rng.next() * Double(items.count)) % items.count]
    }

    /// Köylü hedefine vardı (sim haber verir): noktadaki kalma süresi şimdi başlar.
    public mutating func arrived() {
        if let dwell = pendingDwell {
            pendingDwell = nil
            timer = dwell
        }
    }

    /// Hedefi baştan seç (ör. köylü başka odaya taşındı): şimdiki etkinliğin ilk hedefi.
    public mutating func reset() {
        needGoal = true
        queued = nil
        atSpot = nil
        pendingDwell = nil
    }

    public mutating func setActivity(_ activity: AvatarActivity, finishedNow: Bool) {
        if finishedNow { pendingCheer = true }
        guard activity != self.activity || finishedNow else { return }
        self.activity = activity
        needGoal = true
        queued = nil
        atSpot = nil
    }

    public mutating func advance(dt: Double, freeSpots: [RoomSpot.Kind]) -> Decision? {
        guard let activity else { return nil }
        if needGoal {
            needGoal = false
            if pendingCheer, activity != .away {
                pendingCheer = false
                queued = (.cheer, 0.3)
                // Süre köylü masanın yanına varınca başlar (yürüyüş uzun sürebilir; sevinç yarıda kalmasın).
                pendingDwell = 0.3 + AvatarClip.cheer.duration + 0.2
                timer = .infinity
                atDesk = false
                return .goal(.stand(loop: .idle))
            }
            return startGoal(for: activity)
        }
        if var q = queued {
            q.after -= dt
            if q.after <= 0 {
                queued = nil
                timer -= dt
                return .oneShot(q.clip)
            }
            queued = q
        }
        timer -= dt
        guard timer <= 0 else { return nil }
        switch activity {
        case .typing:
            let clip = pick([AvatarClip.sitSip, .sitThink, .sitStretch])
            timer = random(8...20) + clip.duration
            return .oneShot(clip)
        case .waving:
            let clip = pick([AvatarClip.waitTap, .lookAround])
            timer = clip.duration + AvatarClip.wave.duration * random(2...3)
            return .oneShot(clip)
        case .dozing:
            return wander(freeSpots: freeSpots)
        case .away:
            timer = .infinity
            return nil
        }
    }

    private mutating func startGoal(for activity: AvatarActivity) -> Decision {
        atSpot = nil
        pendingDwell = nil
        atDesk = activity == .typing || activity == .dozing
        switch activity {
        case .typing:
            timer = random(8...20)
            return .goal(.seat(loop: .sitType))
        case .waving:
            timer = AvatarClip.wave.duration * random(2...3)
            return .goal(.stand(loop: .wave))
        case .dozing:
            timer = random(20...60)
            return .goal(.seat(loop: .sitDoze))
        case .away:
            timer = .infinity
            return .goal(.leave)
        }
    }

    /// Boşta: masadaysa boş bir noktaya git; noktadaysa ya başka bir noktaya ya da masaya dön.
    private mutating func wander(freeSpots: [RoomSpot.Kind]) -> Decision? {
        let choices = freeSpots.filter { $0 != atSpot }
        let goBack = atSpot != nil && (choices.isEmpty || rng.next() < 0.5)
        if goBack || (atSpot == nil && choices.isEmpty) {
            if atSpot == nil && atDesk {
                // Gidecek yer yok: masada uyumaya devam.
                timer = random(20...60)
                return nil
            }
            // Noktadan (ya da sevinçten sonra ayakta) masaya dön.
            atSpot = nil
            atDesk = true
            timer = random(20...60)
            return .goal(.seat(loop: .sitDoze))
        }
        let kind = pick(choices)
        atSpot = kind
        atDesk = false
        let goal: AvatarGoal
        switch kind {
        case .sofa: goal = .spot(.sofa, loop: .sofaSit, oneShot: nil, dwell: random(10...30))
        case .plant: goal = .spot(.plant, loop: .lookAround, oneShot: .inspect, dwell: AvatarClip.inspect.duration + random(3...6))
        case .waterCooler: goal = .spot(.waterCooler, loop: .idle, oneShot: .drink, dwell: AvatarClip.drink.duration + random(2...5))
        case .coffeeTable: goal = .spot(.coffeeTable, loop: .idle, oneShot: .stretch, dwell: AvatarClip.stretch.duration + random(2...5))
        case .bookshelf: goal = .spot(.bookshelf, loop: .readBook, oneShot: nil, dwell: random(12...30))
        case .arcade: goal = .spot(.arcade, loop: .playArcade, oneShot: nil, dwell: random(12...30))
        case .whiteboard: goal = .spot(.whiteboard, loop: .drawBoard, oneShot: nil, dwell: random(12...30))
        case .coffeeMachine: goal = .spot(.coffeeMachine, loop: .idle, oneShot: .brewCoffee,
                                         dwell: AvatarClip.brewCoffee.duration + random(2...4))
        }
        // Kalma süresi köylü varınca başlar (`arrived`); o zamana kadar karar yok.
        if case .spot(_, _, _, let dwell) = goal { pendingDwell = dwell; timer = .infinity }
        return .goal(goal)
    }
}
