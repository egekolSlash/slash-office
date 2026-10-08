/// Köylü özelleştirme önizlemesi (ofis hayatı §C4): köylü sırayla ayakta hareketler yapar; döngüler iki tur,
/// tek seferlikler bir kez; sıra baştan tekrarlar.
public enum PreviewClips {
    public static let sequence: [AvatarClip] = [.idle, .wave, .lookAround, .stretch, .cheer, .readBook, .playArcade, .waitTap]

    public static func span(of clip: AvatarClip) -> Double { clip.loops ? clip.duration * 2 : clip.duration }

    public static var period: Double { sequence.reduce(0) { $0 + span(of: $1) } }

    public static func clip(at time: Double) -> AvatarClip {
        var t = time.truncatingRemainder(dividingBy: period)
        if t < 0 { t += period }
        for clip in sequence {
            let s = span(of: clip)
            if t < s { return clip }
            t -= s
        }
        return sequence[0]
    }
}
