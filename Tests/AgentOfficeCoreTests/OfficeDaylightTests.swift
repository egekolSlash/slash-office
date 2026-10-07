import Foundation
import Testing
import simd
@testable import AgentOfficeCore

@Suite struct OfficeDaylightTests {
    func luminance(_ c: SIMD3<Double>) -> Double { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }

    /// Öğlen bugünkü (v5) gündüzle aynı: gökyüzü sRGB (194, 224, 252), güneş önden-yukarıdan.
    @Test func noonIsTheClassicDay() {
        let l = OfficeDaylight.at(hour: 13)
        #expect(simd_length(l.sky - SIMD3(194, 224, 252) / 255) < 0.03)
        #expect(l.emissive == 1)
        #expect(l.direction.y < -0.7)                 // yukarıdan aşağı
        #expect(l.direction.z < 0)                    // kameranın tarafından (önden) vurur
        #expect(l.stars == 0)
    }

    @Test func midnightIsDarkWithGlowingWindowsAndStars() {
        let l = OfficeDaylight.at(hour: 0.5)
        #expect(luminance(l.sky) < 0.12)
        #expect(luminance(l.sun) < 0.15 && l.sun.z > l.sun.x)   // soluk mavi ay ışığı
        #expect(l.emissive >= 2.5)
        #expect(l.stars > 0.9)
        #expect(luminance(l.skyAmbient) < luminance(OfficeDaylight.at(hour: 13).skyAmbient) / 2)
    }

    @Test(arguments: [6.6, 19.3])
    func sunriseAndSunsetAreWarm(hour: Double) {
        let l = OfficeDaylight.at(hour: hour)
        #expect(l.sky.x > l.sky.z)                    // kızıl gökyüzü
        #expect(l.sun.x > l.sun.z * 1.3)
    }

    /// Güneş sabah soldan (−x), akşam sağdan (+x) vurur.
    @Test func sunCrossesFromLeftToRight() {
        #expect(OfficeDaylight.at(hour: 8.5).direction.x > 0.2)   // ışık +x'e doğru gider: güneş solda
        #expect(OfficeDaylight.at(hour: 17.5).direction.x < -0.2)
    }

    /// Dakikadan dakikaya sıçrama yok (renk, ışık yönü, parlaklık).
    @Test func changesAreSmoothMinuteByMinute() {
        var previous = OfficeDaylight.at(hour: 0)
        for minute in 1...(24 * 60) {
            let l = OfficeDaylight.at(hour: Double(minute) / 60)
            #expect(simd_length(l.sky - previous.sky) < 0.03, "gökyüzü \(minute)")
            #expect(simd_length(l.sun - previous.sun) < 0.03, "güneş \(minute)")
            #expect(simd_dot(l.direction, previous.direction) > cos(1.5 * .pi / 180), "yön \(minute)")
            #expect(abs(l.emissive - previous.emissive) < 0.08 && abs(l.stars - previous.stars) < 0.08)
            #expect(abs(simd_length(l.direction) - 1) < 1e-9 && l.direction.y < -0.2)  // ışık hep yukarıdan
            previous = l
        }
    }

    /// Oda içi sıcak ışığı: gece tam, gündüz yok, arada yumuşak.
    @Test func interiorLightIsOnAtNightOffAtDay() {
        #expect(OfficeDaylight.at(hour: 23).interior > 0.95)
        #expect(OfficeDaylight.at(hour: 13).interior == 0)
        let dusk = OfficeDaylight.at(hour: 20).interior
        #expect(dusk > 0.2 && dusk < 0.95)
        var previous = OfficeDaylight.at(hour: 0).interior
        for minute in 1...(24 * 60) {
            let v = OfficeDaylight.at(hour: Double(minute) / 60).interior
            #expect(abs(v - previous) < 0.05)
            previous = v
        }
    }

    @Test func hourOfDayReadsTheLocalClock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 21, minute: 30))!
        #expect(abs(OfficeDaylight.hour(of: date, calendar: calendar) - 21.5) < 1e-9)
    }
}
