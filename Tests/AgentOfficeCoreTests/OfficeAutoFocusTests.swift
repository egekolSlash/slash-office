import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct OfficeAutoFocusTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    func c(_ id: String, _ state: AgentState, finished: Bool = false, open: Bool = false, at seconds: Double = 0) -> OfficeAutoFocus.Candidate {
        OfficeAutoFocus.Candidate(id: id, state: state, unseenFinish: finished, openInPane: open,
                                  since: t0.addingTimeInterval(seconds))
    }

    @Test func questionWinsOverWorkingOverFinished() {
        let pick = OfficeAutoFocus.pick([c("w", .working(tool: nil)), c("f", .idle, finished: true),
                                         c("q", .waiting(.question("?")))], current: nil)
        #expect(pick == "q")
        // İşi bitip görülmemiş en düşük öncelikte: çalışan ondan önce gelir, ama başka kimse yoksa ona dönülür.
        #expect(OfficeAutoFocus.pick([c("w", .working(tool: nil)), c("f", .idle, finished: true)], current: nil) == "w")
        #expect(OfficeAutoFocus.pick([c("i", .idle), c("f", .idle, finished: true)], current: nil) == "f")
        #expect(OfficeAutoFocus.pick([c("w", .working(tool: nil)), c("i", .idle)], current: nil) == "w")
    }

    /// Kullanıcının panelde zaten açık tuttuğu oturum yerine bakmadığı oturum öne çıkar (aynı öncelikte).
    @Test func sessionsNotOpenInAPaneComeFirst() {
        let three = [c("a", .idle, finished: true, open: true, at: 9), c("b", .idle, finished: true, open: true, at: 8),
                     c("c", .idle, finished: true, open: false, at: 1)]
        #expect(OfficeAutoFocus.pick(three, current: nil) == "c")
        // Ama bir soru, açık panelde olsa da bitmiş işten önce gelir.
        let asked = [c("a", .waiting(.permission("Bash")), open: true), c("c", .idle, finished: true)]
        #expect(OfficeAutoFocus.pick(asked, current: nil) == "a")
    }

    /// Aynı öncelikte durumuna en son giren kazanır: bir ajana bakarken başka biri çalışmaya başlarsa kamera ona döner.
    @Test func newestArrivalWinsWithinTheSameClass() {
        let two = [c("old", .waiting(.question("?")), at: 1), c("new", .waiting(.question("?")), at: 5)]
        #expect(OfficeAutoFocus.pick(two, current: nil) == "new")
        #expect(OfficeAutoFocus.pick(two, current: "old") == "new")
        let working = [c("watched", .working(tool: nil), at: 1), c("started", .working(tool: nil), at: 9)]
        #expect(OfficeAutoFocus.pick(working, current: "watched") == "started")
        // Daha yüksek bir sınıf çıkınca geçer.
        #expect(OfficeAutoFocus.pick([c("old", .working(tool: nil)), c("q", .waiting(.question("?")))], current: "old") == "q")
    }

    /// Eşitlikte baktığımız masada kalınır (kamera zıplamasın).
    @Test func tiesKeepTheCurrentDesk() {
        let two = [c("a", .working(tool: nil), at: 3), c("b", .working(tool: nil), at: 3)]
        #expect(OfficeAutoFocus.pick(two, current: "a") == "a")
        #expect(OfficeAutoFocus.pick(two, current: "b") == "b")
    }

    @Test func nothingHappeningMeansNoFocus() {
        #expect(OfficeAutoFocus.pick([c("i", .idle), c("e", .exited), c("s", .starting)], current: nil) == nil)
        #expect(OfficeAutoFocus.pick([], current: "x") == nil)
    }

    /// Elle hareketten sonraki duraklama sadece daha önemsiz geçişleri engeller: yeni bir soru yine kamerayı döndürür.
    @Test func aNewQuestionOverridesTheManualPause() {
        let now = t0
        let paused = now.addingTimeInterval(-1)
        let question = c("q", .waiting(.question("?")))
        #expect(OfficeAutoFocus.shouldApply(target: "q", current: "w", candidates: [question, c("w", .working(tool: nil))],
                                            lastManualMove: paused, now: now))
        #expect(!OfficeAutoFocus.shouldApply(target: "w", current: nil, candidates: [c("w", .working(tool: nil))],
                                             lastManualMove: paused, now: now))
        // Zaten o soruya bakıyorsa tekrar uygulanmaz.
        #expect(!OfficeAutoFocus.shouldApply(target: "q", current: "q", candidates: [question], lastManualMove: paused, now: now))
        #expect(OfficeAutoFocus.shouldApply(target: "w", current: nil, candidates: [c("w", .working(tool: nil))],
                                            lastManualMove: nil, now: now))
    }

    @Test func manualMovePausesAutoFocusForAWhile() {
        let now = t0
        #expect(!OfficeAutoFocus.isPaused(lastManualMove: nil, now: now))
        #expect(OfficeAutoFocus.isPaused(lastManualMove: now.addingTimeInterval(-2), now: now))
        #expect(OfficeAutoFocus.manualPause == 3)
        #expect(!OfficeAutoFocus.isPaused(lastManualMove: now.addingTimeInterval(-OfficeAutoFocus.manualPause - 1), now: now))
    }
}

@Suite struct OfficeCardLayoutTests {
    let size = (width: 900.0, height: 600.0)
    let card = (width: 130.0, height: 34.0)

    func overlaps(_ a: OfficeOverlay.CardFrame, _ b: OfficeOverlay.CardFrame) -> Bool {
        let s = (a.scale + b.scale) / 2
        let w: Double = card.width * s - 0.5, h: Double = card.height * s - 0.5
        return abs(a.x - b.x) < w && abs(a.y - b.y) < h
    }

    /// Kart başın yanında durur, üstünde değil.
    @Test func cardSitsBesideTheHead() {
        let frames = OfficeOverlay.layoutCards([("a", (x: 300.0, y: 300.0))], headRadius: 20, cardSize: card, viewSize: size)
        let f = frames["a"]!
        #expect(f.x - card.width / 2 >= 300 + 20)                       // başın sağında
        #expect(abs(f.y - 300) <= card.height)                          // aynı hizada
    }

    @Test(arguments: [3, 6, 10])
    func cardsDoNotOverlap(count: Int) {
        // Yan yana ve üst üste yakın başlar.
        var anchors: [(String, (x: Double, y: Double))] = []
        for i in 0..<count {
            let x: Double = 300 + Double(i % 3) * 60
            let y: Double = 250 + Double(i / 3) * 25
            anchors.append(("d\(i)", (x: x, y: y)))
        }
        let frames = OfficeOverlay.layoutCards(anchors, headRadius: 18, cardSize: card, viewSize: size)
        #expect(frames.count >= count - 1)                                  // sığmayan uzaktaki gizlenebilir
        let all = Array(frames.values)
        for (i, a) in all.enumerated() {
            for b in all.dropFirst(i + 1) { #expect(!overlaps(a, b), "\(a) \(b)") }
            #expect(a.x - card.width / 2 >= -0.5 && a.x + card.width / 2 <= size.width + 0.5)
        }
    }

    /// Kart başka köylülerin başını ve tabelaları örtmez.
    @Test func cardsAvoidOtherHeadsAndSigns() {
        let anchors: [(String, (x: Double, y: Double))] = [("a", (x: 300, y: 300)), ("b", (x: 360, y: 300)), ("c", (x: 420, y: 300))]
        let sign = OfficeOverlay.Obstacle(x: 520, y: 300, width: 110, height: 24)
        let frames = OfficeOverlay.layoutCards(anchors, headRadius: 18, cardSize: card, viewSize: size, avoiding: [sign])
        for (_, f) in frames {
            for (_, head) in anchors {
                let coversHead = abs(f.x - head.x) < card.width / 2 + 18 && abs(f.y - head.y) < card.height / 2 + 18
                #expect(!coversHead, "\(f) başı örtüyor \(head)")
            }
            #expect(!(abs(f.x - sign.x) < (card.width + sign.width) / 2 && abs(f.y - sign.y) < (card.height + sign.height) / 2))
        }
    }

    /// Uzaktaki kart yer bulamazsa yakındakinin üstüne binmez, gizlenir.
    @Test func farCardThatWouldCoverANearOneIsHidden() {
        let small = (width: 330.0, height: 90.0)
        let anchors: [(String, (x: Double, y: Double))] = [("near", (x: 150, y: 50)), ("far", (x: 160, y: 40))]
        let frames = OfficeOverlay.layoutCards(anchors, headRadius: 10, cardSize: card, viewSize: small)
        #expect(frames["near"] != nil)
        if let far = frames["far"], let near = frames["near"] {
            #expect(!overlaps(far, near))
        }
    }

    /// Yakın planda kartın başın yanında, kenarlara taşmadan duracak yeri yok: yine gösterilir, ekrana sığdırılır
    /// (gizlenirse hiçbir kart görünmüyordu). Gizleme sadece daha yakındaki bir kartın üstüne binecek olana.
    @Test func cardWithNoRoomBesideTheHeadIsClampedOnScreen() {
        let tight = (width: 260.0, height: 120.0)
        let frames = OfficeOverlay.layoutCards([("only", (x: 130, y: 60))], headRadius: 40, cardSize: card, viewSize: tight)
        let frame = try? #require(frames["only"])
        #expect(frame != nil)
        if let frame {
            #expect(frame.x - card.width / 2 >= -0.001 && frame.x + card.width / 2 <= tight.width + 0.001)
            #expect(frame.y - card.height / 2 >= -0.001 && frame.y + card.height / 2 <= tight.height + 0.001)
        }
    }

    /// Engel (başka bir baş ya da tabela) yüzünden yer bulamayan kart da gösterilir; sadece kartlar çakışmaz.
    @Test func obstaclesDoNotHideTheOnlyCard() {
        let view = (width: 400.0, height: 300.0)
        let wall = OfficeOverlay.Obstacle(x: 200, y: 150, width: 400, height: 300)
        let frames = OfficeOverlay.layoutCards([("a", (x: 200, y: 150))], headRadius: 10, cardSize: card, viewSize: view,
                                               avoiding: [wall])
        #expect(frames["a"] != nil)
    }

    /// Odaktaki kart önce yerleşir: başının hemen sağındaki yeri o alır.
    @Test func prioritizedCardIsPlacedFirst() {
        let anchors: [(String, (x: Double, y: Double))] = [("front", (x: 300, y: 320)), ("focus", (x: 320, y: 300))]
        let frames = OfficeOverlay.layoutCards(anchors, headRadius: 18, cardSize: card, viewSize: size, priority: ["focus"])
        let f = frames["focus"]!
        #expect(abs(f.x - (320 + 18 + 6 + card.width / 2)) < 1e-9 && abs(f.y - 300) < 1e-9)
    }

    /// Küçültülmüş (uzaktaki) kart küçük boyutuyla yerleşir.
    @Test func scaledCardsTakeLessRoom() {
        let anchors: [(String, (x: Double, y: Double))] = [("a", (x: 300, y: 300))]
        let f = OfficeOverlay.layoutCards(anchors, headRadius: 18, cardSize: card, viewSize: size, scales: ["a": 0.7])["a"]!
        #expect(f.scale == 0.7)
        #expect(abs(f.x - (300 + 18 * 0.7 + 6 + card.width * 0.7 / 2)) < 1e-9)   // uzaktaki baş da küçük
    }

    @Test func cardNearTheRightEdgeGoesLeft() {
        let f = OfficeOverlay.layoutCards([("a", (x: 880.0, y: 300.0))], headRadius: 20, cardSize: card, viewSize: size)["a"]!
        #expect(f.x + card.width / 2 <= 880 - 20)
    }

    @Test func layoutIsDeterministicAndOrderIndependent() {
        let anchors = [("a", (x: 300.0, y: 300.0)), ("b", (x: 330.0, y: 310.0)), ("c", (x: 360.0, y: 290.0))]
        let one = OfficeOverlay.layoutCards(anchors, headRadius: 18, cardSize: card, viewSize: size)
        let two = OfficeOverlay.layoutCards(anchors.reversed(), headRadius: 18, cardSize: card, viewSize: size)
        #expect(one == two)
    }
}
