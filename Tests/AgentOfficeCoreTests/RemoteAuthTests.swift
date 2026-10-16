import Foundation
import Testing
@testable import AgentOfficeCore

final class TestClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}

@Suite struct RemoteAuthTests {
    func makeAuth(_ clock: TestClock = TestClock()) -> (RemoteAuth, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("remote-\(UUID().uuidString)/devices.json")
        return (RemoteAuth(fileURL: url, now: { clock.date }), url)
    }

    @Test func correctCodePairsOnce() throws {
        let (auth, _) = makeAuth()
        let code = auth.newPairingCode()
        #expect(code.count == 6 && code.allSatisfy(\.isNumber))
        let token = try #require(auth.pair(code: code, deviceName: "iPhone"))
        #expect(auth.device(forToken: token)?.name == "iPhone")
        #expect(auth.pair(code: code, deviceName: "Other") == nil)
        #expect(auth.currentCode == nil)
    }

    @Test func fiveWrongAttemptsBurnTheCode() {
        let (auth, _) = makeAuth()
        let code = auth.newPairingCode()
        let wrong = code == "000000" ? "111111" : "000000"
        for _ in 0..<RemoteAuth.maxAttempts { #expect(auth.pair(code: wrong, deviceName: "x") == nil) }
        #expect(auth.pair(code: code, deviceName: "x") == nil)
    }

    @Test func codeExpiresAfterTwoMinutes() {
        let clock = TestClock()
        let (auth, _) = makeAuth(clock)
        let code = auth.newPairingCode()
        clock.date += RemoteAuth.codeLifetime + 1
        #expect(auth.currentCode == nil)
        #expect(auth.pair(code: code, deviceName: "x") == nil)
    }

    @Test func revokedTokenStopsWorking() throws {
        let (auth, _) = makeAuth()
        let token = try #require(auth.pair(code: auth.newPairingCode(), deviceName: "iPhone"))
        let device = try #require(auth.device(forToken: token))
        auth.revoke(device.id)
        #expect(auth.device(forToken: token) == nil)
        #expect(auth.devices.isEmpty)
    }

    @Test func onlyTheHashIsStoredAndItSurvivesRestart() throws {
        let (auth, url) = makeAuth()
        let token = try #require(auth.pair(code: auth.newPairingCode(), deviceName: "iPhone"))
        let file = try String(contentsOf: url, encoding: .utf8)
        #expect(!file.contains(token))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        let reloaded = RemoteAuth(fileURL: url)
        #expect(reloaded.device(forToken: token)?.name == "iPhone")
    }

    @Test func blankDeviceNameFallsBack() throws {
        let (auth, _) = makeAuth()
        let token = try #require(auth.pair(code: auth.newPairingCode(), deviceName: "   "))
        #expect(auth.device(forToken: token)?.name == "Phone")
    }
}
