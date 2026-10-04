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

    /// Ham hook JSON'unu tek satırlık zarfa çevirir. Geçersiz JSON'da nil döner.
    public static func encodeLine(session: String, provider: String, rawPayload: Data) -> Data? {
        guard let payload = try? JSONDecoder().decode(JSONValue.self, from: rawPayload) else { return nil }
        return try? JSONEncoder().encode(HookEnvelope(session: session, provider: provider, payload: payload))
    }
}
