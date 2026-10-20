import CryptoKit
import Foundation

/// RFC 6455'in sunucu tarafı: el sıkışma ve çerçeveler. Parçalı mesaj desteklenmez (tarayıcılar küçük metinleri
/// tek çerçevede yollar); istemci çerçevesi maskeli olmalı.
public enum WebSocket {
    static let guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    public static let maxPayload = 1 << 20

    public enum Opcode: UInt8, Sendable {
        case continuation = 0, text = 1, binary = 2, close = 8, ping = 9, pong = 10
    }

    public struct Frame: Equatable, Sendable {
        public var opcode: Opcode
        public var payload: Data

        public init(opcode: Opcode, payload: Data) {
            self.opcode = opcode
            self.payload = payload
        }
    }

    public enum DecodeResult: Equatable, Sendable {
        case incomplete
        case invalid
        case frame(Frame, consumed: Int)
    }

    public static func acceptKey(for key: String) -> String {
        Data(Insecure.SHA1.hash(data: Data((key + guid).utf8))).base64EncodedString()
    }

    public static func handshake(key: String) -> Data {
        Data(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
              + "Sec-WebSocket-Accept: \(acceptKey(for: key))\r\n\r\n").utf8)
    }

    /// Sunucu çerçevesi: maskesiz, tek parça.
    public static func encode(_ opcode: Opcode, _ payload: Data) -> Data {
        var out = Data([0x80 | opcode.rawValue])
        switch payload.count {
        case ..<126:
            out.append(UInt8(payload.count))
        case ..<65_536:
            out.append(126)
            out.append(UInt8(payload.count >> 8))
            out.append(UInt8(payload.count & 0xFF))
        default:
            out.append(127)
            for shift in stride(from: 56, through: 0, by: -8) { out.append(UInt8((UInt64(payload.count) >> UInt64(shift)) & 0xFF)) }
        }
        return out + payload
    }

    public static func decode(_ input: Data) -> DecodeResult {
        let buffer = Data(input)
        let header = [UInt8](buffer.prefix(14))
        guard header.count >= 2 else { return .incomplete }
        guard header[0] & 0x80 != 0, header[0] & 0x70 == 0,
              let opcode = Opcode(rawValue: header[0] & 0x0F), opcode != .continuation,
              header[1] & 0x80 != 0 else { return .invalid }
        var length = Int(header[1] & 0x7F)
        var index = 2
        if length == 126 {
            guard header.count >= 4 else { return .incomplete }
            length = Int(header[2]) << 8 | Int(header[3])
            index = 4
        } else if length == 127 {
            guard header.count >= 10 else { return .incomplete }
            var value: UInt64 = 0
            for byte in header[2..<10] { value = value << 8 | UInt64(byte) }
            guard value <= UInt64(maxPayload) else { return .invalid }
            length = Int(value)
            index = 10
        }
        guard length <= maxPayload, opcode.rawValue < 8 || length <= 125 else { return .invalid }
        guard header.count >= index + 4 else { return .incomplete }
        let mask = Array(header[index..<(index + 4)])
        index += 4
        guard buffer.count >= index + length else { return .incomplete }
        var payload = [UInt8](buffer[index..<(index + length)])
        for i in payload.indices { payload[i] ^= mask[i % 4] }
        return .frame(Frame(opcode: opcode, payload: Data(payload)), consumed: index + length)
    }

    public static func closePayload(code: UInt16) -> Data {
        Data([UInt8(code >> 8), UInt8(code & 0xFF)])
    }
}
