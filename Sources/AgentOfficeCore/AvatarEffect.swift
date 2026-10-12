import Foundation
import simd

/// Baş üstü efektleri (duygu = yüz + küçük hareket + efekt). Kameraya dönük küçük kartlar
/// olarak çizilir; burada yalnız ne, nerede, ne boyda ve ne saydamlıkta olduğu hesaplanır (test edilebilir).
public enum AvatarEffect: Int, CaseIterable, Sendable {
    /// Doku dizisi katmanı sırası (`OfficeEffects` çizer).
    case sweat, notice, sparkle, sleep, note

    /// Başa göre (metre; x sağ, y yukarı, z kameraya) konum, boy ve saydamlık.
    public struct Sprite: Equatable, Sendable {
        public var effect: AvatarEffect
        public var offset: SIMD3<Float>
        public var size: Float
        public var alpha: Float
    }

    /// Köylünün o anki efekti: izin beklerken ter damlası, soru gelince "!" çizgileri, sevinçte parıltı,
    /// uyuklarken "z"ler, atari oynarken nota.
    public static func current(clip: AvatarClip, waitReason: AvatarInstance.WaitReason?, clipTime: Double) -> AvatarEffect? {
        switch clip {
        case .notice: return .notice
        case .cheer: return .sparkle
        case .sitDoze: return .sleep
        case .playArcade: return .note
        default: return waitReason == .permission ? .sweat : nil
        }
    }

    /// Efektin kartları `time` anında (sn, döngüsel). Ofset baş tepesine göre.
    public func sprites(time t: Double) -> [Sprite] {
        func cycle(_ period: Double, _ phase: Double = 0) -> Float { Float(((t / period + phase).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)) }
        switch self {
        case .sweat:
            // Şakaktan aşağı kayan, sonra sönen damla.
            let p = cycle(1.6)
            return [Sprite(effect: self, offset: SIMD3(0.27, -0.08 - 0.10 * p, 0.05), size: 0.11, alpha: min(1, (1 - p) * 2.5))]
        case .notice:
            // Başın üstünde "!" çizgileri: hızla büyüyüp hafifçe titrer.
            let p = cycle(0.75)
            let pop = min(1, p * 4)
            return [Sprite(effect: self, offset: SIMD3(0, 0.14 + 0.02 * pop, 0), size: 0.22 + 0.08 * pop, alpha: 1)]
        case .sparkle:
            // Başın çevresinde sırayla parlayan üç yıldız.
            return (0..<3).map { i in
                let p = cycle(0.9, Double(i) / 3)
                let a = Float(i) * 2.1 + 0.6
                let r: Float = 0.30
                return Sprite(effect: self, offset: SIMD3(r * cos(a), -0.05 + 0.18 * sin(a) + 0.04 * p, 0.05),
                              size: 0.06 + 0.07 * sin(.pi * p), alpha: sin(.pi * p))
            }
        case .sleep:
            // Yükselip büyüyen ve sönen iki "z".
            return (0..<2).map { i in
                let p = cycle(2.4, Double(i) / 2)
                return Sprite(effect: self, offset: SIMD3(0.14 + 0.10 * p, 0.02 + 0.22 * p, 0), size: 0.07 + 0.07 * p,
                              alpha: min(1, (1 - p) * 2, p * 6))
            }
        case .note:
            let p = cycle(1.2)
            return [Sprite(effect: self, offset: SIMD3(-0.22 + 0.05 * sin(Float(t) * 4), 0.02 + 0.18 * p, 0), size: 0.13,
                           alpha: min(1, (1 - p) * 2, p * 6))]
        }
    }
}
