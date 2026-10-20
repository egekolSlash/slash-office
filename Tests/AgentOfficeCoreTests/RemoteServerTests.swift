import Foundation
import Testing
@testable import AgentOfficeCore

final class CommandLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ClientMessage] = []
    func add(_ message: ClientMessage) { lock.withLock { items.append(message) } }
    var all: [ClientMessage] { lock.withLock { items } }

    func wait(count: Int, timeout: TimeInterval = 2) async -> [ClientMessage] {
        let deadline = Date().addingTimeInterval(timeout)
        while all.count < count, Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        return all
    }
}

final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    var isOpen: Bool { lock.withLock { opened } }
    func open() { lock.withLock { opened = true } }
}

@Suite(.serialized) struct RemoteServerTests {
    struct Running {
        let server: RemoteServer
        let auth: RemoteAuth
        let port: UInt16
        let log: CommandLog
    }

    func startServer(command: (@Sendable (ClientMessage) async -> String?)? = nil) async throws -> Running {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("remote-server-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("<h1>Slash</h1>".utf8).write(to: dir.appendingPathComponent("index.html"))
        let auth = RemoteAuth(fileURL: dir.appendingPathComponent("devices.json"))
        let log = CommandLog()
        let routes = RemoteRoutes(auth: auth, staticRoot: dir, sessions: { [] }, transcript: { _, _ in nil })
        let server = RemoteServer(handlers: .init(routes: routes,
                                                  command: command ?? { log.add($0); return nil },
                                                  welcome: { [.sessions([])] }))
        let port = try await server.start(host: "127.0.0.1", port: 0)
        return Running(server: server, auth: auth, port: port, log: log)
    }

    func socket(_ running: Running) -> URLSessionWebSocketTask {
        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(running.port)/api/stream")!)
        task.resume()
        return task
    }

    func receiveText(_ task: URLSessionWebSocketTask) async throws -> [String: Any] {
        guard case .string(let text) = try await task.receive() else { return [:] }
        return try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] ?? [:]
    }

    @Test func servesTheWebAppOverHTTP() async throws {
        let running = try await startServer()
        defer { running.server.stop() }
        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(running.port)/")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(data == Data("<h1>Slash</h1>".utf8))
    }

    @Test func apiWithoutTokenIs401() async throws {
        let running = try await startServer()
        defer { running.server.stop() }
        let (_, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(running.port)/api/sessions")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 401)
    }

    @Test func authenticatedSocketGetsReadyThenSessions() async throws {
        let running = try await startServer()
        defer { running.server.stop() }
        let token = try #require(running.auth.pair(code: running.auth.newPairingCode(), deviceName: "p"))
        let task = socket(running)
        try await task.send(.string(#"{"type":"auth","token":"\#(token)"}"#))
        #expect(try await receiveText(task)["type"] as? String == "ready")
        #expect(try await receiveText(task)["type"] as? String == "sessions")
        running.server.broadcast(.transcriptChanged(sessionId: "s1"))
        #expect(try await receiveText(task)["sessionId"] as? String == "s1")
        task.cancel(with: .goingAway, reason: nil)
    }

    @Test func commandsArriveInOrder() async throws {
        let running = try await startServer()
        defer { running.server.stop() }
        let token = try #require(running.auth.pair(code: running.auth.newPairingCode(), deviceName: "p"))
        let task = socket(running)
        try await task.send(.string(#"{"type":"auth","token":"\#(token)"}"#))
        _ = try await receiveText(task)
        for text in ["bir", "iki", "üç"] {
            try await task.send(.string(#"{"type":"send.text","sessionId":"s","text":"\#(text)"}"#))
        }
        let received = await running.log.wait(count: 3)
        #expect(received == ["bir", "iki", "üç"].map { .sendText(sessionId: "s", text: $0) })
        task.cancel(with: .goingAway, reason: nil)
    }

    @Test func messagesBeforeAuthCloseTheSocket() async throws {
        let running = try await startServer()
        defer { running.server.stop() }
        let task = socket(running)
        try await task.send(.string(#"{"type":"send.text","sessionId":"s","text":"rm"}"#))
        await #expect(throws: (any Error).self) { _ = try await task.receive() }
        #expect(running.log.all.isEmpty)

        let wrong = socket(running)
        try await wrong.send(.string(#"{"type":"auth","token":"nope"}"#))
        await #expect(throws: (any Error).self) { _ = try await wrong.receive() }
    }

    @Test func revokedDevicesQueuedCommandsDoNotRun() async throws {
        let log = CommandLog()
        let gate = Gate()
        let running = try await startServer(command: { message in
            log.add(message)
            while !gate.isOpen { try? await Task.sleep(for: .milliseconds(5)) }
            return nil
        })
        defer { running.server.stop() }
        let token = try #require(running.auth.pair(code: running.auth.newPairingCode(), deviceName: "p"))
        let device = try #require(running.auth.device(forToken: token))
        let task = socket(running)
        try await task.send(.string(#"{"type":"auth","token":"\#(token)"}"#))
        _ = try await receiveText(task)
        for text in ["bir", "iki", "üç"] {
            try await task.send(.string(#"{"type":"send.text","sessionId":"s","text":"\#(text)"}"#))
        }
        let first = await log.wait(count: 1)
        #expect(first.count == 1)
        running.auth.revoke(device.id)
        running.server.disconnect(deviceId: device.id)
        gate.open()
        try await Task.sleep(for: .milliseconds(300))
        #expect(log.all == [.sendText(sessionId: "s", text: "bir")])
    }

    @Test func revokedDeviceIsDisconnected() async throws {
        let running = try await startServer()
        defer { running.server.stop() }
        let token = try #require(running.auth.pair(code: running.auth.newPairingCode(), deviceName: "p"))
        let device = try #require(running.auth.device(forToken: token))
        let task = socket(running)
        try await task.send(.string(#"{"type":"auth","token":"\#(token)"}"#))
        _ = try await receiveText(task)
        _ = try await receiveText(task)
        running.auth.revoke(device.id)
        running.server.disconnect(deviceId: device.id)
        await #expect(throws: (any Error).self) { _ = try await task.receive() }
    }
}
