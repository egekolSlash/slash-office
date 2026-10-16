import Foundation

/// Telefona sunulan web uygulamasının dosyaları: yalnızca bu adlar sunulur (yol gezintisi yok).
public enum RemoteStatic {
    public static let folder = "Remote"
    public static let files: [String: String] = [
        "index.html": "text/html; charset=utf-8",
        "app.js": "text/javascript; charset=utf-8",
        "app.css": "text/css; charset=utf-8",
        "manifest.json": "application/manifest+json",
    ]

    /// Önce uygulama paketi, sonra depo (paketsiz çalışma).
    public static func find(bundleResources: URL?, repoRoot: URL,
                            fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL? {
        let candidates = [bundleResources?.appendingPathComponent(folder),
                          repoRoot.appendingPathComponent("Resources/\(folder)")].compactMap { $0 }
        return candidates.first { fileExists($0.appendingPathComponent("index.html").path) }
    }
}

/// HTTP uçları (spec §7). Ağdan bağımsız: istek alır, cevap döner.
public struct RemoteRoutes: Sendable {
    public var auth: RemoteAuth
    public var staticRoot: URL?
    public var sessions: @Sendable () async -> [RemoteSession]
    /// `after` nil ise son mesajlar (ilk açılış).
    public var transcript: @Sendable (_ sessionId: String, _ after: UInt64?) async -> TranscriptPage?

    public init(auth: RemoteAuth, staticRoot: URL?, sessions: @escaping @Sendable () async -> [RemoteSession],
                transcript: @escaping @Sendable (_ sessionId: String, _ after: UInt64?) async -> TranscriptPage?) {
        self.auth = auth
        self.staticRoot = staticRoot
        self.sessions = sessions
        self.transcript = transcript
    }

    public func respond(to request: HTTPRequest) async -> HTTPResponse {
        if request.method == "GET", request.path == "/" { return staticFile("index.html") }
        if request.method == "POST", request.path == "/api/pair" { return pair(request) }
        if request.path.hasPrefix("/api/") {
            guard let token = request.bearerToken, auth.device(forToken: token) != nil else { return .error(401, "unauthorized") }
            return await api(request)
        }
        let name = String(request.path.dropFirst())
        if request.method == "GET", RemoteStatic.files[name] != nil { return staticFile(name) }
        return .error(404, "not_found")
    }

    func api(_ request: HTTPRequest) async -> HTTPResponse {
        guard request.method == "GET" else { return .error(405, "method_not_allowed") }
        let parts = request.path.split(separator: "/").map(String.init)
        if parts == ["api", "sessions"] { return .json(await sessions()) }
        if parts.count == 4, parts[1] == "sessions", parts[3] == "transcript" {
            let after = request.query["after"].flatMap { UInt64($0) }
            guard let page = await transcript(parts[2], after) else { return .error(404, "no_transcript") }
            return .json(page)
        }
        return .error(404, "not_found")
    }

    func pair(_ request: HTTPRequest) -> HTTPResponse {
        struct Body: Decodable {
            let code: String
            let deviceName: String
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: request.body) else { return .error(400, "bad_request") }
        guard let token = auth.pair(code: body.code, deviceName: body.deviceName) else { return .error(401, "wrong_code") }
        return .json(["token": token])
    }

    func staticFile(_ name: String) -> HTTPResponse {
        guard let type = RemoteStatic.files[name], let root = staticRoot,
              let data = try? Data(contentsOf: root.appendingPathComponent(name)) else { return .error(404, "not_found") }
        return HTTPResponse(status: 200, contentType: type, body: data)
    }
}
