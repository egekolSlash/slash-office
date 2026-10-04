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

    /// Uygulamanın kullanmadığı, MB'larca olabilen alanlar. Ajanı bekletmemek ve socket'i tıkamamak için atılır.
    static let droppedPayloadKeys = ["tool_response"]

    /// Ham hook JSON'unu tek satırlık zarfa çevirir. Geçersiz JSON'da nil döner.
    public static func encodeLine(session: String, provider: String, rawPayload: Data) -> Data? {
        guard var object = (try? JSONSerialization.jsonObject(with: rawPayload)) as? [String: Any] else { return nil }
        for key in droppedPayloadKeys { object[key] = nil }
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
