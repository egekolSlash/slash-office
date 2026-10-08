import Foundation

/// Köylünün gideceği yer ve orada oynayacağı döngü.
public enum AvatarGoal: Equatable, Sendable {
    /// Masada, taburede otur (sitType ya da sitDoze).
    case seat(loop: AvatarClip)
    /// Masanın yanında ayakta dur (wave; iş bitince sevinmek için idle).
    case stand(loop: AvatarClip)
    /// Dinlenme köşesindeki bir noktaya git: varınca tek seferlik hareket (varsa), sonra döngü; `dwell` sn kal.
    case spot(RoomSpot.Kind, loop: AvatarClip?, oneShot: AvatarClip?, dwell: Double)
    /// Bütün eşyalar doluyken odada boş bir noktada dur: döngü (etrafa bakma, gerinme, bekleme), `dwell` sn.
    case point(PlanPoint, loop: AvatarClip, dwell: Double)
    /// Kapıdan çık.
    case leave
}

/// Köylünün davranışı (v5 spec §5): sabit tohumlu, kendi saatiyle karar veren durum makinesi. Ne yapacağına karar
/// verir; yürüme, klipler ve rezervasyon `AvatarSim`'dedir.
/// - Çalışıyor: masada `sitType`; 8–20 sn'de bir `sitSip` / `sitThink` / `sitStretch` / `sitDraw` / `sitWrite` / `sitRead`.
/// - Bekliyor: masanın yanında `wave`; 2–3 el sallamada bir `waitTap` / `lookAround`.
/// - Boşta (ofis hayatı): masada oturup beklemez; boş bir eşyaya gider, kalır, sonra başka bir eşyaya (son ikisini
///   tekrar seçmez). Eşya kalmadıysa odada boş bir noktada etrafa bakar; o da yoksa masanın yanında ayakta bekler.
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
    /// Son gidilen iki eşya (tekrar seçilmez).
    private var recent: [RoomSpot.Kind] = []
    /// Eşyada kalırken ara hareket: arcade'de sevinç, tahtada geri çekilip bakma (aralıklı), kahveden sonra içme (bir kez).
    private var extra: (clip: AvatarClip, interval: ClosedRange<Double>?, timer: Double)?

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
            switch atSpot {
            case .arcade?: extra = (.cheer, 4...7, random(4...7))
            case .whiteboard?: extra = (.stepBackLook, 5...8, random(5...8))
            case .coffeeMachine?: extra = (.drink, nil, AvatarClip.brewCoffee.duration + 0.3)
            default: extra = nil
            }
        }
    }

    /// Hedefi baştan seç (ör. köylü başka odaya taşındı): şimdiki etkinliğin ilk hedefi.
    public mutating func reset() {
        needGoal = true
        queued = nil
        atSpot = nil
        pendingDwell = nil
        extra = nil
    }

    public mutating func setActivity(_ activity: AvatarActivity, finishedNow: Bool) {
        if finishedNow { pendingCheer = true }
        guard activity != self.activity || finishedNow else { return }
        self.activity = activity
        needGoal = true
        queued = nil
        atSpot = nil
        extra = nil
    }

    /// `freePoints`: eşya kalmadıysa gidilebilecek boş noktalar (sim önerir).
    public mutating func advance(dt: Double, freeSpots: [RoomSpot.Kind], freePoints: [PlanPoint] = []) -> Decision? {
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
            if activity == .dozing { return wander(freeSpots: freeSpots, freePoints: freePoints) }
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
        if var e = extra {
            e.timer -= dt
            if e.timer <= 0 {
                if let interval = e.interval { e.timer = random(interval); extra = e } else { extra = nil }
                timer -= dt
                return .oneShot(e.clip)
            }
            extra = e
        }
        timer -= dt
        guard timer <= 0 else { return nil }
        switch activity {
        case .typing:
            let clip = pick([AvatarClip.sitSip, .sitThink, .sitStretch, .sitDraw, .sitWrite, .sitRead])
            timer = random(8...20) + clip.duration
            return .oneShot(clip)
        case .waving:
            let clip = pick([AvatarClip.waitTap, .lookAround])
            timer = clip.duration + AvatarClip.wave.duration * random(2...3)
            return .oneShot(clip)
        case .dozing:
            return wander(freeSpots: freeSpots, freePoints: freePoints)
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
            // Boşta masada beklenmez (advance doğrudan `wander`'a gider); buraya sadece güvenlik için.
            timer = random(6...12)
            return .goal(.stand(loop: .idle))
        case .away:
            timer = .infinity
            return .goal(.leave)
        }
    }

    /// Boşta: son iki eşya dışında boş bir eşyaya git; yoksa odada boş bir noktaya; o da yoksa masanın yanında dur.
    private mutating func wander(freeSpots: [RoomSpot.Kind], freePoints: [PlanPoint]) -> Decision? {
        atDesk = false
        extra = nil
        var choices = freeSpots.filter { !recent.contains($0) }
        if choices.isEmpty, freePoints.isEmpty { choices = freeSpots.filter { $0 != recent.last } }
        guard !choices.isEmpty else {
            atSpot = nil
            let loop = pick([AvatarClip.lookAround, .stretch, .idle])
            let dwell = random(6...12)
            pendingDwell = dwell
            timer = .infinity
            if freePoints.isEmpty { return .goal(.stand(loop: .idle)) }
            return .goal(.point(pick(freePoints), loop: loop, dwell: dwell))
        }
        let kind = pick(choices)
        atSpot = kind
        recent = Array((recent + [kind]).suffix(2))
        let goal: AvatarGoal
        switch kind {
        case .sofa: goal = .spot(.sofa, loop: .sofaSit, oneShot: nil, dwell: random(10...30))
        case .plant: goal = .spot(.plant, loop: .lookAround, oneShot: .inspect, dwell: AvatarClip.inspect.duration + random(3...6))
        case .waterCooler: goal = .spot(.waterCooler, loop: .idle, oneShot: .drink, dwell: AvatarClip.drink.duration + random(2...5))
        case .coffeeTable: goal = .spot(.coffeeTable, loop: .idle, oneShot: .stretch, dwell: AvatarClip.stretch.duration + random(2...5))
        case .bookshelf: goal = .spot(.bookshelf, loop: .readBook, oneShot: nil, dwell: random(12...30))
        case .arcade: goal = .spot(.arcade, loop: .playArcade, oneShot: nil, dwell: random(12...30))
        case .whiteboard: goal = .spot(.whiteboard, loop: .drawBoard, oneShot: nil, dwell: random(12...30))
        case .coffeeMachine:
            goal = .spot(.coffeeMachine, loop: .idle, oneShot: .brewCoffee,
                         dwell: AvatarClip.brewCoffee.duration + AvatarClip.drink.duration + random(1...3))
        }
        // Kalma süresi köylü varınca başlar (`arrived`); o zamana kadar karar yok.
        if case .spot(_, _, _, let dwell) = goal { pendingDwell = dwell; timer = .infinity }
        return .goal(goal)
    }
}
