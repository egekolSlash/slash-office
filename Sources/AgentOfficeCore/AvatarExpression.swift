import Foundation

/// Karakterin yüz ifadesi: oynayan klip, beklemenin türü ve görünüşün dinlenme ağzından göz ve ağız dokusu katmanı,
/// ayrıca köylüye özgü aralıklarla göz kırpma. Katman sırası karakter paketindeki `eyeExpressions` / `mouthExpressions`.
public enum AvatarExpression {
    public struct Face: Equatable, Sendable {
        public var eye: Int
        public var mouth: Int
        public init(eye: Int, mouth: Int) { self.eye = eye; self.mouth = mouth }
    }

    // Göz: normal, mutlu (^), iri (şaşkın), uykulu (—), endişeli (kaşlı), yan bakış, kapalı (‿), odaklı (kısık).
    public static let normal = 0, happy = 1, wide = 2, sleepy = 3, worriedEyes = 4, side = 5, closed = 6, focused = 7
    // Ağız: gülümseme, açık gülüş, kahkaha, somurtma, endişeli, korkmuş, düz, küçük "o", "o".
    public static let smile = 0, open = 1, laugh = 2, frown = 3, worried = 4, scared = 5, flat = 6, ooh = 7, wow = 8

    public static func resting(_ mouth: AvatarLook.Mouth) -> Int {
        switch mouth {
        case .smile: smile
        case .open: open
        case .flat: flat
        }
    }

    public static func face(clip: AvatarClip, waitReason: AvatarInstance.WaitReason?, restingMouth: Int, time: Double,
                            seed: UInt64) -> Face {
        var face: Face
        switch clip {
        case .cheer: face = Face(eye: happy, mouth: laugh)
        case .sitDoze: face = Face(eye: sleepy, mouth: flat)
        case .sitStretch, .stretch: face = Face(eye: closed, mouth: open)
        case .sitSip, .drink, .brewCoffee: face = Face(eye: closed, mouth: flat)
        case .sitThink, .stepBackLook: face = Face(eye: side, mouth: flat)
        case .sitType, .sitDraw, .sitWrite, .sitRead, .readBook, .drawBoard: face = Face(eye: focused, mouth: flat)
        case .playArcade: face = Face(eye: happy, mouth: open)
        case .scratchHead: face = Face(eye: worriedEyes, mouth: worried)
        case .notice: face = Face(eye: wide, mouth: wow)
        case .wave, .waitTap, .lookAround: face = Face(eye: wide, mouth: ooh)
        default: face = Face(eye: normal, mouth: restingMouth)
        }
        switch waitReason {
        case .permission?: face = Face(eye: worriedEyes, mouth: worried)
        case .question? where clip == .walk || clip == .idle: face = Face(eye: wide, mouth: ooh)
        default: break
        }
        if blinking(time: time, seed: seed), ![happy, sleepy, closed].contains(face.eye) { face.eye = closed }
        return face
    }

    /// Köylüye özgü (seed) 3–5,5 sn aralıkla 0,13 sn göz kırpma.
    public static func blinking(time: Double, seed: UInt64) -> Bool {
        let period = 3.0 + Double(seed % 1000) / 400
        let phase = Double((seed >> 10) % 1000) / 1000 * period
        let t = (time + phase).truncatingRemainder(dividingBy: period)
        return t < 0.13
    }
}
