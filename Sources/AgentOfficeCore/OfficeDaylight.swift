import Foundation
import simd

/// Cihazın saatine göre ofis ışığı (gece/gündüz döngüsü): gökyüzü rengi, güneş (ya da ay) ışığının rengi ve yönü,
/// ortam ışığı, gece parlayan pencere/lamba/monitör (emissive) çarpanı ve yıldızlar. Ara saatler anahtar karelerin
/// arasında yumuşakça karışır; öğlen v5'teki sabit gündüzün aynısıdır.
public enum OfficeDaylight {
    public struct Lighting: Equatable, Sendable {
        /// Gökyüzü (arka plan) rengi, sRGB.
        public var sky: SIMD3<Double>
        /// Güneş ya da ay ışığı, doğrusal (şiddetiyle).
        public var sun: SIMD3<Double>
        /// Yukarı ve aşağı bakan yüzlerin ortam ışığı, doğrusal.
        public var skyAmbient: SIMD3<Double>
        public var groundAmbient: SIMD3<Double>
        /// Işığın gidiş yönü (birim; hep yukarıdan aşağı).
        public var direction: SIMD3<Double>
        /// Kendi ışığı olan yüzeylerin (pencere, lamba, ekran) çarpanı: gündüz 1, gece daha parlak.
        public var emissive: Double
        /// Yıldızların görünürlüğü (0…1).
        public var stars: Double
    }

    struct Key {
        var hour: Double
        var sky, sun, skyAmbient, groundAmbient: SIMD3<Double>
        var emissive: Double
        var stars: Double
    }

    static let night = Key(hour: 0, sky: SIMD3(0.06, 0.08, 0.18), sun: SIMD3(0.10, 0.13, 0.22),
                           skyAmbient: SIMD3(0.14, 0.16, 0.26), groundAmbient: SIMD3(0.07, 0.07, 0.10), emissive: 3.0, stars: 1)
    static let day = Key(hour: 0, sky: SIMD3(194, 224, 252) / 255, sun: SIMD3(1.0, 0.92, 0.80) * 0.72,
                         skyAmbient: SIMD3(0.46, 0.47, 0.46), groundAmbient: SIMD3(0.34, 0.33, 0.26), emissive: 1, stars: 0)
    static let dawn = Key(hour: 0, sky: SIMD3(0.30, 0.26, 0.45), sun: SIMD3(0.20, 0.16, 0.20),
                          skyAmbient: SIMD3(0.22, 0.21, 0.30), groundAmbient: SIMD3(0.12, 0.11, 0.13), emissive: 2.2, stars: 0.3)
    static let sunrise = Key(hour: 0, sky: SIMD3(0.98, 0.72, 0.58), sun: SIMD3(0.62, 0.40, 0.26),
                             skyAmbient: SIMD3(0.36, 0.33, 0.36), groundAmbient: SIMD3(0.24, 0.21, 0.19), emissive: 1.4, stars: 0)
    static let sunset = Key(hour: 0, sky: SIMD3(0.99, 0.66, 0.52), sun: SIMD3(0.66, 0.40, 0.24),
                            skyAmbient: SIMD3(0.40, 0.34, 0.36), groundAmbient: SIMD3(0.26, 0.22, 0.19), emissive: 1.3, stars: 0)

    /// Anahtar kareler (yerel saat): gece → şafak → gün doğumu → gündüz → gün batımı → alacakaranlık → gece.
    static let keys: [Key] = {
        func at(_ h: Double, _ k: Key) -> Key { var k = k; k.hour = h; return k }
        return [at(0, night), at(4.5, night), at(5.5, dawn), at(6.5, sunrise), at(8.5, day), at(17.5, day),
                at(19, sunset), at(20, dawn), at(21, night), at(24, night)]
    }()

    static let sunrise_h = 6.5, sunset_h = 19.5
    static let moonDirection = simd_normalize(SIMD3(-0.3, -0.85, -0.45))

    public static func at(hour rawHour: Double) -> Lighting {
        let hour = (rawHour.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
        let i = keys.lastIndex { $0.hour <= hour } ?? 0
        let a = keys[i], b = keys[min(i + 1, keys.count - 1)]
        let t = b.hour > a.hour ? (hour - a.hour) / (b.hour - a.hour) : 0
        func mix(_ x: SIMD3<Double>, _ y: SIMD3<Double>) -> SIMD3<Double> { x + (y - x) * t }
        return Lighting(sky: mix(a.sky, b.sky), sun: mix(a.sun, b.sun), skyAmbient: mix(a.skyAmbient, b.skyAmbient),
                        groundAmbient: mix(a.groundAmbient, b.groundAmbient), direction: direction(hour: hour),
                        emissive: a.emissive + (b.emissive - a.emissive) * t, stars: a.stars + (b.stars - a.stars) * t)
    }

    /// Güneş gün boyunca soldan (sabah, −x) sağa (akşam, +x) geçer ve hep kameranın tarafından (önden) vurur; gölgeler
    /// gün doğumu ve batımında uzar. Gece ışık aydan gelir; ikisi ufuk çevresinde yumuşakça karışır.
    static func direction(hour: Double) -> SIMD3<Double> {
        let altitude = 62 * sin(Double.pi * (hour - sunrise_h) / (sunset_h - sunrise_h))   // derece; gece negatif
        let lit = max(altitude, 18) * .pi / 180
        let across = min(max((hour - 13) / 6.5, -1), 1)
        let horizontal = simd_normalize(SIMD3(across * 0.9, 0, 0.7))
        let sunPosition = horizontal * cos(lit) + SIMD3(0, sin(lit), 0)
        let sun = -sunPosition
        let e = min(max((altitude + 10) / 24, 0), 1)
        let w = e * e * (3 - 2 * e)
        return simd_normalize(moonDirection + (sun - moonDirection) * w)
    }

    /// Yerel saat (0…24, kesirli).
    public static func hour(of date: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }
}
