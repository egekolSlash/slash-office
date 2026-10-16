import Foundation

/// Telefonun gördüğü oturum (spec §5): durum, bekleme nedeni, iş özeti, todo'lar.
public struct RemoteSession: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case starting, idle, working, permission, question, exited }
    public var id: String
    public var title: String
    public var status: Status
    /// Çalışırken tool adı; beklerken soru ya da izin metni.
    public var detail: String?
    public var summary: String?
    public var todos: [RemoteTodo]
    public var finishedUnseen: Bool
    /// Telefondan mesaj gönderilebilir mi (oturum bu Mac'te bir panelde çalışıyor).
    public var canSend: Bool
}

public struct RemoteTodo: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case pending, inProgress, done }
    public var title: String
    public var status: Status
}

public struct RemoteMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant, tool }
    public var id: String
    public var role: Role
    public var text: String
    public var time: String?
}

/// Transkriptten okunan mesajlar ve bir sonraki okumanın başlayacağı bayt.
public struct TranscriptPage: Codable, Equatable, Sendable {
    public var messages: [RemoteMessage]
    public var cursor: UInt64
}

/// Mac → telefon (WebSocket).
public enum ServerEvent: Equatable, Sendable {
    case ready
    case sessions([RemoteSession])
    /// Transkript değişti; telefon yeni mesajları kendi imlecinden HTTP ile çeker.
    case transcriptChanged(sessionId: String)
    /// Hata kodu (`not_running`, `invalid_text`, `bad_message`); telefon kendi dilinde gösterir.
    case error(String)
}

extension ServerEvent: Encodable {
    private enum Keys: String, CodingKey { case type, sessions, sessionId, code }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .ready:
            try container.encode("ready", forKey: .type)
        case .sessions(let list):
            try container.encode("sessions", forKey: .type)
            try container.encode(list, forKey: .sessions)
        case .transcriptChanged(let id):
            try container.encode("transcript.changed", forKey: .type)
            try container.encode(id, forKey: .sessionId)
        case .error(let code):
            try container.encode("error", forKey: .type)
            try container.encode(code, forKey: .code)
        }
    }

    public func jsonData() -> Data {
        (try? RemoteJSON.encoder().encode(self)) ?? Data()
    }
}

/// Telefon → Mac (WebSocket).
public enum ClientMessage: Equatable, Sendable {
    case auth(token: String)
    case sendText(sessionId: String, text: String)
    case interrupt(sessionId: String)
}

extension ClientMessage: Decodable {
    private enum Keys: String, CodingKey { case type, token, sessionId, text }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "auth":
            self = .auth(token: try container.decode(String.self, forKey: .token))
        case "send.text":
            self = .sendText(sessionId: try container.decode(String.self, forKey: .sessionId),
                             text: try container.decode(String.self, forKey: .text))
        case "interrupt":
            self = .interrupt(sessionId: try container.decode(String.self, forKey: .sessionId))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "unknown type \(other)")
        }
    }
}

public enum RemoteJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum RemoteSnapshot {
    /// Telefondaki liste: bekleyenler üstte (spec §5), aynı sınıfta store sırası.
    public static func sessions(_ sessions: [AgentStore.Session], canSend: (String) -> Bool) -> [RemoteSession] {
        let mapped = sessions.map { session in
            RemoteSession(id: session.id, title: session.title, status: status(session.state), detail: detail(session.state),
                          summary: session.workSummary, todos: session.todos.map(todo),
                          finishedUnseen: session.unseenFinish && session.state != .exited,
                          canSend: session.state != .exited && canSend(session.id))
        }
        return mapped.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    static func rank(_ session: RemoteSession) -> Int {
        switch session.status {
        case .permission: 0
        case .question: 1
        case .working: 2
        case .idle: session.finishedUnseen ? 3 : 4
        case .starting: 5
        case .exited: 6
        }
    }

    static func status(_ state: AgentState) -> RemoteSession.Status {
        switch state {
        case .starting: .starting
        case .idle: .idle
        case .working: .working
        case .waiting(.permission): .permission
        case .waiting(.question): .question
        case .exited: .exited
        }
    }

    static func detail(_ state: AgentState) -> String? {
        switch state {
        case .working(let tool): tool
        case .waiting(.permission(let text)), .waiting(.question(let text)): text.isEmpty ? nil : text
        default: nil
        }
    }

    static func todo(_ item: TodoItem) -> RemoteTodo {
        let status: RemoteTodo.Status = switch item.status {
        case .pending: .pending
        case .inProgress: .inProgress
        case .done: .done
        }
        return RemoteTodo(title: item.title, status: status)
    }
}
