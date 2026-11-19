import Foundation

public struct HookEnvelope: Codable, Equatable, Sendable {
    public var session: String
    public var provider: String
    public var payload: JSONValue

    public init(session: String, provider: String, payload: JSONValue) {
        self.session = session
        self.provider = provider
        self.payload = payload
    }

    /// Araç çıktısı MB'larca olabilir; ajanı bekletmemek ve socket'i tıkamamak için atılır. Sadece arka plan işini
    /// tanımaya yarayan kısa alanlar kalır (Bash `backgroundTaskId`, Agent `status` / `agentId`).
    static let keptResponseKeys: Set<String> = ["backgroundTaskId", "status", "agentId"]

    /// Sadece sözlük çıktının kısa (metin ya da sayı) izinli alanları; kalmazsa alan tamamen atılır.
    static func trimmedResponse(_ response: Any?) -> [String: Any]? {
        guard let response = response as? [String: Any] else { return nil }
        let kept = response.filter { key, value in
            keptResponseKeys.contains(key) && (value is NSNumber || (value as? String).map { $0.count <= 200 } == true)
        }
        return kept.isEmpty ? nil : kept
    }

    /// Ham hook JSON'unu tek satırlık zarfa çevirir. Geçersiz JSON'da nil döner.
    public static func encodeLine(session: String, provider: String, rawPayload: Data) -> Data? {
        guard var object = (try? JSONSerialization.jsonObject(with: rawPayload)) as? [String: Any] else { return nil }
        object["tool_response"] = trimmedResponse(object["tool_response"])
        guard let payload = try? JSONSerialization.data(withJSONObject: object),
              let session = try? JSONEncoder().encode(session),
              let provider = try? JSONEncoder().encode(provider) else { return nil }
        var line = Data(#"{"session":"#.utf8)
        line.append(session)
        line.append(contentsOf: Data(#","provider":"#.utf8))
        line.append(provider)
        line.append(contentsOf: Data(#","payload":"#.utf8))
        line.append(payload)
        line.append(contentsOf: Data("}".utf8))
        return line
    }
}
