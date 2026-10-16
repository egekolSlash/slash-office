import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct HTTPMessageTests {
    func parse(_ text: String) -> HTTPParseResult { HTTPParser.parse(Data(text.utf8)) }

    @Test func parsesGetWithQueryAndBearer() throws {
        let raw = "GET /api/sessions/s1/transcript?after=120 HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer abc\r\n\r\n"
        guard case .request(let request, let consumed) = parse(raw) else { Issue.record("not parsed"); return }
        #expect(request.method == "GET")
        #expect(request.path == "/api/sessions/s1/transcript")
        #expect(request.query["after"] == "120")
        #expect(request.bearerToken == "abc")
        #expect(consumed == raw.utf8.count)
    }

    @Test func waitsForTheWholeBody() {
        #expect(parse("POST /api/pair HTTP/1.1\r\nContent-Length: 10\r\n\r\n{\"a\"") == .incomplete)
        #expect(parse("GET / HTTP/1.1\r\nHost: x\r\n") == .incomplete)
    }

    @Test func readsTheBody() {
        guard case .request(let request, _) = parse("POST /api/pair HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}") else {
            Issue.record("not parsed"); return
        }
        #expect(request.body == Data("{}".utf8))
    }

    @Test func rejectsOversizedAndBrokenRequests() {
        let huge = "GET / HTTP/1.1\r\nX: " + String(repeating: "a", count: HTTPParser.maxHeaderBytes) + "\r\n\r\n"
        #expect(parse(huge) == .invalid(status: 431))
        #expect(parse("POST / HTTP/1.1\r\nContent-Length: 999999\r\n\r\n") == .invalid(status: 413))
        #expect(parse("NONSENSE\r\n\r\n") == .invalid(status: 400))
    }

    @Test func detectsWebSocketUpgrade() {
        let raw = "GET /api/stream HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
        guard case .request(let request, _) = parse(raw) else { Issue.record("not parsed"); return }
        #expect(request.isWebSocketUpgrade)
    }

    @Test func responseSerializes() {
        let text = String(decoding: HTTPResponse.error(401, "unauthorized").serialized(), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
        #expect(text.contains("Content-Type: application/json; charset=utf-8\r\n"))
        #expect(text.contains("Cache-Control: no-store\r\n"))
        #expect(text.hasSuffix("\r\n\r\n{\"error\":\"unauthorized\"}"))
    }
}
