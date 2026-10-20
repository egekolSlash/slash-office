import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct RemoteRoutesTests {
    func makeRoutes(transcript: TranscriptPage? = nil) throws -> (RemoteRoutes, RemoteAuth) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("remote-static-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("<h1>Slash</h1>".utf8).write(to: dir.appendingPathComponent("index.html"))
        try Data("console.log(1)".utf8).write(to: dir.appendingPathComponent("app.js"))
        try Data("secret".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        let auth = RemoteAuth(fileURL: dir.appendingPathComponent("devices.json"))
        let session = RemoteSession(id: "s1", title: "proj", status: .idle, detail: nil, summary: nil, todos: [],
                                    finishedUnseen: false, canSend: true)
        let routes = RemoteRoutes(auth: auth, staticRoot: dir, sessions: { [session] in [session] }, transcript: { id, _ in id == "s1" ? transcript : nil })
        return (routes, auth)
    }

    func request(_ method: String, _ path: String, token: String? = nil, body: String = "", query: [String: String] = [:]) -> HTTPRequest {
        var headers: [String: String] = [:]
        if let token { headers["authorization"] = "Bearer \(token)" }
        return HTTPRequest(method: method, path: path, query: query, headers: headers, body: Data(body.utf8))
    }

    @Test func servesOnlyListedStaticFiles() async throws {
        let (routes, _) = try makeRoutes()
        let index = await routes.respond(to: request("GET", "/"))
        #expect(index.status == 200 && index.contentType.hasPrefix("text/html") && index.body == Data("<h1>Slash</h1>".utf8))
        #expect(await routes.respond(to: request("GET", "/app.js")).contentType.hasPrefix("text/javascript"))
        #expect(await routes.respond(to: request("GET", "/notes.txt")).status == 404)
        #expect(await routes.respond(to: request("GET", "/../devices.json")).status == 404)
    }

    @Test func apiNeedsAToken() async throws {
        let (routes, _) = try makeRoutes()
        #expect(await routes.respond(to: request("GET", "/api/sessions")).status == 401)
        #expect(await routes.respond(to: request("GET", "/api/sessions", token: "wrong")).status == 401)
    }

    @Test func pairingThenSessions() async throws {
        let (routes, auth) = try makeRoutes()
        let code = auth.newPairingCode()
        let paired = await routes.respond(to: request("POST", "/api/pair", body: #"{"code":"\#(code)","deviceName":"iPhone"}"#))
        #expect(paired.status == 200)
        let token = try #require((try JSONSerialization.jsonObject(with: paired.body) as? [String: String])?["token"])
        let list = await routes.respond(to: request("GET", "/api/sessions", token: token))
        #expect(list.status == 200)
        #expect(try RemoteJSON.decoder().decode([RemoteSession].self, from: list.body).map(\.id) == ["s1"])
    }

    @Test func wrongCodeIsRefused() async throws {
        let (routes, auth) = try makeRoutes()
        auth.newPairingCode()
        #expect(await routes.respond(to: request("POST", "/api/pair", body: #"{"code":"x","deviceName":"a"}"#)).status == 401)
        #expect(await routes.respond(to: request("POST", "/api/pair", body: "nope")).status == 400)
    }

    @Test func transcriptRoute() async throws {
        let page = TranscriptPage(messages: [RemoteMessage(id: "u:0", role: .user, text: "hi", time: nil)], cursor: 42)
        let (routes, auth) = try makeRoutes(transcript: page)
        let token = try #require(auth.pair(code: auth.newPairingCode(), deviceName: "p"))
        let found = await routes.respond(to: request("GET", "/api/sessions/s1/transcript", token: token, query: ["after": "10"]))
        #expect(try RemoteJSON.decoder().decode(TranscriptPage.self, from: found.body) == page)
        #expect(await routes.respond(to: request("GET", "/api/sessions/zz/transcript", token: token)).status == 404)
        #expect(await routes.respond(to: request("DELETE", "/api/sessions", token: token)).status == 405)
    }

    @Test func findsTheStaticFolder() {
        let repo = URL(fileURLWithPath: "/repo")
        let found = RemoteStatic.find(bundleResources: nil, repoRoot: repo, fileExists: { $0 == "/repo/Resources/Remote/index.html" })
        #expect(found?.path == "/repo/Resources/Remote")
        #expect(RemoteStatic.find(bundleResources: nil, repoRoot: repo, fileExists: { _ in false }) == nil)
    }
}
