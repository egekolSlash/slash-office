import Foundation
import Testing
@testable import AgentOfficeCore

final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [HookEnvelope] = []
    func add(_ envelope: HookEnvelope) { lock.withLock { items.append(envelope) } }
    var all: [HookEnvelope] { lock.withLock { items } }

    func wait(count: Int, timeout: TimeInterval = 2) async -> [HookEnvelope] {
        let deadline = Date().addingTimeInterval(timeout)
        while all.count < count, Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        return all
    }
}

func tempSocketPath() -> String { "/tmp/ao-test-\(UUID().uuidString.prefix(8)).sock" }

func line(_ session: String, _ event: String, extra: String = "") -> Data {
    HookEnvelope.encodeLine(session: session, provider: "claude",
                            rawPayload: Data(#"{"hook_event_name":"\#(event)"\#(extra)}"#.utf8))!
}

@Suite(.serialized) struct HookServerTests {
    @Test func receivesEnvelopesInOrder() async throws {
        let path = tempSocketPath()
        let collector = Collector()
        let server = HookServer(socketPath: path) { collector.add($0) }
        try server.start()
        defer { server.stop() }
        for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"] {
            #expect(HookClient.send(line("s1", event), toSocket: path))
        }
        let received = await collector.wait(count: 5)
        #expect(received.map { $0.payload["hook_event_name"]?.string } == ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"])
    }

    @Test func replacesStaleSocketFile() async throws {
        let path = tempSocketPath()
        FileManager.default.createFile(atPath: path, contents: Data("stale".utf8))
        let collector = Collector()
        let server = HookServer(socketPath: path) { collector.add($0) }
        try server.start()
        defer { server.stop() }
        #expect(HookClient.send(line("s", "Stop"), toSocket: path))
        #expect(await collector.wait(count: 1).count == 1)
    }

    @Test func handlesLargePayload() async throws {
        let path = tempSocketPath()
        let collector = Collector()
        let server = HookServer(socketPath: path) { collector.add($0) }
        try server.start()
        defer { server.stop() }
        let big = String(repeating: "x", count: 2_000_000)
        #expect(HookClient.send(line("s", "PostToolUse", extra: #","last_assistant_message":"\#(big)""#), toSocket: path, timeout: 2))
        let received = await collector.wait(count: 1)
        #expect(received.first?.payload["last_assistant_message"]?.string?.count == 2_000_000)
    }

    @Test func ignoresGarbageLines() async throws {
        let path = tempSocketPath()
        let collector = Collector()
        let server = HookServer(socketPath: path) { collector.add($0) }
        try server.start()
        defer { server.stop() }
        HookClient.send(Data("garbage".utf8), toSocket: path)
        HookClient.send(line("s", "Stop"), toSocket: path)
        let received = await collector.wait(count: 1)
        #expect(received.count == 1)
    }

    @Test func stopRemovesSocketFile() throws {
        let path = tempSocketPath()
        let server = HookServer(socketPath: path) { _ in }
        try server.start()
        #expect(FileManager.default.fileExists(atPath: path))
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func stoppingReplacedServerKeepsNewServersSocket() async throws {
        let path = tempSocketPath()
        let old = HookServer(socketPath: path) { _ in }
        try old.start()
        let collector = Collector()
        let new = HookServer(socketPath: path) { collector.add($0) }
        try new.start()
        defer { new.stop() }
        old.stop()
        old.stop() // idempotent
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(HookClient.send(line("s", "Stop"), toSocket: path))
        #expect(await collector.wait(count: 1).count == 1)
    }

    @Test func rejectsTooLongPath() {
        let server = HookServer(socketPath: "/tmp/" + String(repeating: "a", count: 200)) { _ in }
        #expect(throws: HookServerError.self) { try server.start() }
    }
}
