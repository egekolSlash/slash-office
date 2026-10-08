import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct OfficeAutoFocusTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    func c(_ id: String, _ state: AgentState, finished: Bool = false, open: Bool = false, at seconds: Double = 0) -> OfficeAutoFocus.Candidate {
        OfficeAutoFocus.Candidate(id: id, state: state, unseenFinish: finished, openInPane: open,
                                  lastEventAt: t0.addingTimeInterval(seconds))
    }

    @Test func questionWinsOverFinishedOverWorking() {
        let pick = OfficeAutoFocus.pick([c("w", .working(tool: nil)), c("f", .idle, finished: true),
                                         c("q", .waiting(.question("?")))], current: nil)
        #expect(pick == "q")
        #expect(OfficeAutoFocus.pick([c("w", .working(tool: nil)), c("f", .idle, finished: true)], current: nil) == "f")
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

    @Test func soonestEventWinsWithinTheSameClassAndCurrentIsSticky() {
        let two = [c("old", .waiting(.question("?")), at: 1), c("new", .waiting(.question("?")), at: 5)]
        #expect(OfficeAutoFocus.pick(two, current: nil) == "new")
        // Zaten baktığımız aynı sınıftaysa yerinde kalır (kamera zıplamasın).
        #expect(OfficeAutoFocus.pick(two, current: "old") == "old")
        // Daha yüksek bir sınıf çıkınca geçer.
        #expect(OfficeAutoFocus.pick([c("old", .working(tool: nil)), c("q", .waiting(.question("?")))], current: "old") == "q")
    }

    @Test func nothingHappeningMeansNoFocus() {
        #expect(OfficeAutoFocus.pick([c("i", .idle), c("e", .exited), c("s", .starting)], current: nil) == nil)
        #expect(OfficeAutoFocus.pick([], current: "x") == nil)
    }

    /// Elle hareketten sonraki duraklama sadece daha önemsiz geçişleri engeller: yeni bir soru yine kamerayı döndürür.
    @Test func aNewQuestionOverridesTheManualPause() {
        let now = t0
        let paused = now.addingTimeInterval(-5)
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
        #expect(OfficeAutoFocus.isPaused(lastManualMove: now.addingTimeInterval(-10), now: now))
        #expect(!OfficeAutoFocus.isPaused(lastManualMove: now.addingTimeInterval(-OfficeAutoFocus.manualPause - 1), now: now))
    }
}

@Suite struct OfficeCardLayoutTests {
    let size = (width: 900.0, height: 600.0)
    let card = (width: 130.0, height: 34.0)

    func overlaps(_ a: OfficeOverlay.CardFrame, _ b: OfficeOverlay.CardFrame) -> Bool {
        abs(a.x - b.x) < (card.width) - 0.5 && abs(a.y - b.y) < (card.height) - 0.5
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
        #expect(frames.count == count)
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
