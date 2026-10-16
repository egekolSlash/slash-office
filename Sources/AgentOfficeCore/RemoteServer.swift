import Foundation
import Network

/// Uzaktan erişim sunucusu (spec §2, §7): tek adres ve port, HTTP + WebSocket. Her bağlantının durumu tek seri
/// kuyrukta tutulur; uygulama verisi `Handlers` üzerinden async alınır.
public final class RemoteServer: @unchecked Sendable {
    public struct Handlers: Sendable {
        public var routes: RemoteRoutes
        /// WebSocket'ten gelen komut (auth hariç), geliş sırasıyla. Başarıda nil, hatada hata kodu.
        public var command: @Sendable (ClientMessage) async -> String?
        /// Kimliği doğrulanan yeni WebSocket'e `ready`'den sonra gönderilecek ilk olaylar.
        public var welcome: @Sendable () async -> [ServerEvent]

        public init(routes: RemoteRoutes, command: @escaping @Sendable (ClientMessage) async -> String?,
                    welcome: @escaping @Sendable () async -> [ServerEvent]) {
            self.routes = routes
            self.command = command
            self.welcome = welcome
        }
    }

    final class Client: @unchecked Sendable {
        let connection: NWConnection
        var buffer = Data()
        var isWebSocket = false
        var deviceId: String?
        /// `ready` gönderildi; yayınlar ancak bundan sonra bu istemciye gider.
        var isReady = false

        init(connection: NWConnection) { self.connection = connection }
    }

    private final class Once: @unchecked Sendable {
        var done = false
    }

    private let handlers: Handlers
    private let queue = DispatchQueue(label: "agentoffice.remote")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    /// Komutlar sırayla işlenir (iki mesaj terminale ters sırada gitmesin).
    private var commandChain: Task<Void, Never>?

    public init(handlers: Handlers) {
        self.handlers = handlers
    }

    /// Yalnızca `host` adresinde dinler. `port` 0 ise sistem seçer; dinlemeye başlayınca gerçek portu döner.
    public func start(host: String, port: UInt16) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard !once.done else { return }
                    once.done = true
                    continuation.resume(returning: listener.port?.rawValue ?? port)
                case .failed(let error):
                    self?.stop()
                    guard !once.done else { return }
                    once.done = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    guard !once.done else { return }
                    once.done = true
                    continuation.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            queue.async {
                self.listener = listener
                listener.start(queue: self.queue)
            }
        }
    }

    public func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            for client in self.clients.values { client.connection.cancel() }
            self.clients = [:]
        }
    }

    public func broadcast(_ event: ServerEvent) {
        let payload = event.jsonData()
        queue.async {
            for client in self.clients.values where client.isReady { self.sendFrame(client, .text, payload) }
        }
    }

    public func disconnect(deviceId: String) {
        queue.async {
            for client in self.clients.values where client.deviceId == deviceId { self.closeWebSocket(client, code: 4401) }
        }
    }

    // MARK: - Bağlantılar (hepsi `queue` üzerinde)

    private func accept(_ connection: NWConnection) {
        let client = Client(connection: connection)
        let key = ObjectIdentifier(client)
        clients[key] = client
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.clients.removeValue(forKey: key)
            default: break
            }
        }
        connection.start(queue: queue)
        receive(client)
    }

    private func receive(_ client: Client) {
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { client.buffer.append(data) }
            self.process(client)
            if isComplete || error != nil {
                client.connection.cancel()
                return
            }
            if self.clients[ObjectIdentifier(client)] != nil { self.receive(client) }
        }
    }

    private func process(_ client: Client) {
        if client.isWebSocket {
            processFrames(client)
            return
        }
        switch HTTPParser.parse(client.buffer) {
        case .incomplete:
            return
        case .invalid(let status):
            client.buffer = Data()
            respond(client, .error(status, "bad_request"))
        case .request(let request, let consumed):
            client.buffer = Data(client.buffer.dropFirst(consumed))
            if request.path == "/api/stream", request.isWebSocketUpgrade, let key = request.header("sec-websocket-key") {
                client.isWebSocket = true
                client.connection.send(content: WebSocket.handshake(key: key), completion: .contentProcessed { _ in })
                queue.asyncAfter(deadline: .now() + 10) { [weak self] in
                    if client.deviceId == nil { self?.closeWebSocket(client, code: 4401) }
                }
                // El sıkışmayla aynı pakette gelen çerçeve kaybolmasın.
                processFrames(client)
            } else {
                let routes = handlers.routes
                Task {
                    let response = await routes.respond(to: request)
                    self.queue.async { self.respond(client, response) }
                }
            }
        }
    }

    private func respond(_ client: Client, _ response: HTTPResponse) {
        client.connection.send(content: response.serialized(), completion: .contentProcessed { _ in client.connection.cancel() })
    }

    private func processFrames(_ client: Client) {
        while clients[ObjectIdentifier(client)] != nil {
            switch WebSocket.decode(client.buffer) {
            case .incomplete:
                return
            case .invalid:
                closeWebSocket(client, code: 1002)
                return
            case .frame(let frame, let consumed):
                client.buffer = Data(client.buffer.dropFirst(consumed))
                handle(frame, from: client)
            }
        }
    }

    private func handle(_ frame: WebSocket.Frame, from client: Client) {
        switch frame.opcode {
        case .ping: sendFrame(client, .pong, frame.payload)
        case .pong: break
        case .close: closeWebSocket(client, code: 1000)
        case .text: handleText(frame.payload, from: client)
        default: closeWebSocket(client, code: 1003)
        }
    }

    private func handleText(_ payload: Data, from client: Client) {
        guard let message = try? RemoteJSON.decoder().decode(ClientMessage.self, from: payload) else {
            if client.deviceId == nil { closeWebSocket(client, code: 4401) } else { sendFrame(client, .text, ServerEvent.error("bad_message").jsonData()) }
            return
        }
        if case .auth(let token) = message {
            guard client.deviceId == nil, let device = handlers.routes.auth.device(forToken: token) else {
                closeWebSocket(client, code: 4401)
                return
            }
            client.deviceId = device.id
            let welcome = handlers.welcome
            Task {
                let events = await welcome()
                self.queue.async {
                    self.sendFrame(client, .text, ServerEvent.ready.jsonData())
                    client.isReady = true
                    for event in events { self.sendFrame(client, .text, event.jsonData()) }
                }
            }
            return
        }
        guard let deviceId = client.deviceId else {
            closeWebSocket(client, code: 4401)
            return
        }
        let command = handlers.command
        let auth = handlers.routes.auth
        let previous = commandChain
        commandChain = Task {
            await previous?.value
            // Sırada beklerken yetkisi alınan telefonun komutu çalışmaz.
            guard auth.hasDevice(deviceId) else { return }
            if let code = await command(message) {
                self.queue.async { self.sendFrame(client, .text, ServerEvent.error(code).jsonData()) }
            }
        }
    }

    private func sendFrame(_ client: Client, _ opcode: WebSocket.Opcode, _ payload: Data) {
        client.connection.send(content: WebSocket.encode(opcode, payload), completion: .contentProcessed { _ in })
    }

    private func closeWebSocket(_ client: Client, code: UInt16) {
        clients.removeValue(forKey: ObjectIdentifier(client))
        client.connection.send(content: WebSocket.encode(.close, WebSocket.closePayload(code: code)),
                               completion: .contentProcessed { _ in client.connection.cancel() })
    }
}
