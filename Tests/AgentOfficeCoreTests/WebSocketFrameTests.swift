import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct WebSocketFrameTests {
    @Test func acceptKeyMatchesRFC6455() {
        #expect(WebSocket.acceptKey(for: "dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    @Test func decodesTheMaskedHelloFromTheRFC() {
        let bytes: [UInt8] = [0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58]
        #expect(WebSocket.decode(Data(bytes)) == .frame(WebSocket.Frame(opcode: .text, payload: Data("Hello".utf8)), consumed: 11))
    }

    @Test func incompleteAndInvalidFrames() {
        #expect(WebSocket.decode(Data([0x81])) == .incomplete)
        #expect(WebSocket.decode(Data([0x81, 0x85, 0x37, 0xfa])) == .incomplete)
        // Maskesiz istemci çerçevesi
        #expect(WebSocket.decode(Data([0x81, 0x05]) + Data("Hello".utf8)) == .invalid)
        // Parçalı mesaj (FIN yok)
        #expect(WebSocket.decode(Data([0x01, 0x80, 0, 0, 0, 0])) == .invalid)
        // Sınırı aşan uzunluk
        #expect(WebSocket.decode(Data([0x81, 0xFF, 0, 0, 0, 0, 0x10, 0, 0, 0])) == .invalid)
    }

    @Test func encodesLengthsUnmasked() {
        #expect(Array(WebSocket.encode(.text, Data("hi".utf8))) == [0x81, 0x02, 0x68, 0x69])
        let medium = WebSocket.encode(.text, Data(count: 300))
        #expect(Array(medium.prefix(4)) == [0x81, 126, 0x01, 0x2C])
        let large = WebSocket.encode(.binary, Data(count: 70_000))
        #expect(Array(large.prefix(10)) == [0x82, 127, 0, 0, 0, 0, 0, 0x01, 0x11, 0x70])
    }

    @Test func closePayloadCarriesTheCode() {
        #expect(Array(WebSocket.closePayload(code: 4401)) == [0x11, 0x31])
    }
}
