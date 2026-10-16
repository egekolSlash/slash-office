import Foundation

public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    /// Anahtarlar küçük harf.
    public var headers: [String: String]
    public var body: Data

    public func header(_ name: String) -> String? { headers[name.lowercased()] }

    public var bearerToken: String? {
        guard let value = header("authorization"), value.hasPrefix("Bearer ") else { return nil }
        return String(value.dropFirst("Bearer ".count))
    }

    public var isWebSocketUpgrade: Bool {
        header("upgrade")?.lowercased() == "websocket" && header("sec-websocket-key") != nil
    }
}

public enum HTTPParseResult: Equatable, Sendable {
    case incomplete
    case invalid(status: Int)
    case request(HTTPRequest, consumed: Int)
}

/// Uzaktan erişim sunucusunun tek ihtiyacı kadar HTTP/1.1: tek istek, `Content-Length` gövde, chunked yok.
public enum HTTPParser {
    public static let maxHeaderBytes = 16 * 1024
    public static let maxBodyBytes = 64 * 1024

    public static func parse(_ input: Data) -> HTTPParseResult {
        let buffer = Data(input)  // indeksler 0'dan başlasın
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > maxHeaderBytes ? .invalid(status: 431) : .incomplete
        }
        guard end.lowerBound <= maxHeaderBytes else { return .invalid(status: 431) }
        var lines = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return .invalid(status: 400) }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid(status: 400) }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let length = Int(headers["content-length"] ?? "0"), length >= 0 else { return .invalid(status: 400) }
        guard length <= maxBodyBytes else { return .invalid(status: 413) }
        let bodyStart = end.upperBound
        guard buffer.count - bodyStart >= length else { return .incomplete }
        let components = URLComponents(string: String(parts[1]))
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let request = HTTPRequest(method: String(parts[0]), path: components?.path ?? String(parts[1]), query: query,
                                  headers: headers, body: Data(buffer[bodyStart..<(bodyStart + length)]))
        return .request(request, consumed: bodyStart + length)
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public var status: Int
    public var contentType: String
    public var body: Data

    public init(status: Int, contentType: String, body: Data) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }

    public static func json<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        guard let body = try? RemoteJSON.encoder().encode(value) else { return error(500, "encoding") }
        return HTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: body)
    }

    public static func error(_ status: Int, _ code: String) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: Data(#"{"error":"\#(code)"}"#.utf8))
    }

    /// Her cevaptan sonra bağlantı kapanır (`Connection: close`).
    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "X-Content-Type-Options: nosniff\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 413: "Payload Too Large"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        default: "Status"
        }
    }
}
