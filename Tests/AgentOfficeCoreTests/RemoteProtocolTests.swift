import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct RemoteProtocolTests {
    func session(_ id: String, _ state: AgentState, unseen: Bool = false) -> AgentStore.Session {
        var s = AgentStore.Session(id: id, title: "proj-\(id)", cwd: "/p/\(id)", state: state)
        s.unseenFinish = unseen
        return s
    }

    @Test func waitingSessionsComeFirst() {
        let list = RemoteSnapshot.sessions([
            session("a", .exited), session("b", .idle), session("c", .working(tool: "Bash")),
            session("d", .waiting(.question("Renk?"))), session("e", .waiting(.permission("Bash"))),
            session("f", .idle, unseen: true), session("g", .starting),
        ], canSend: { _ in true })
        #expect(list.map(\.id) == ["e", "d", "c", "f", "b", "g", "a"])
    }

    @Test func detailCarriesToolOrQuestion() {
        let list = RemoteSnapshot.sessions([session("c", .working(tool: "Bash")), session("d", .waiting(.question("Renk?")))],
                                           canSend: { _ in true })
        #expect(list.first { $0.id == "c" }?.detail == "Bash")
        #expect(list.first { $0.id == "d" }?.status == .question)
        #expect(list.first { $0.id == "d" }?.detail == "Renk?")
    }

    @Test func exitedSessionCannotSend() {
        let list = RemoteSnapshot.sessions([session("a", .exited), session("b", .idle)], canSend: { _ in true })
        #expect(list.first { $0.id == "a" }?.canSend == false)
        #expect(list.first { $0.id == "b" }?.canSend == true)
    }

    @Test func todosMap() {
        var s = session("a", .working(tool: nil))
        s.todos = [TodoItem(title: "x", status: .inProgress), TodoItem(title: "y", status: .done)]
        let remote = RemoteSnapshot.sessions([s], canSend: { _ in false })[0]
        #expect(remote.todos == [RemoteTodo(title: "x", status: .inProgress), RemoteTodo(title: "y", status: .done)])
    }

    @Test func serverEventsCarryType() throws {
        let object = try JSONSerialization.jsonObject(with: ServerEvent.transcriptChanged(sessionId: "s1").jsonData()) as? [String: Any]
        #expect(object?["type"] as? String == "transcript.changed")
        #expect(object?["sessionId"] as? String == "s1")
        let error = try JSONSerialization.jsonObject(with: ServerEvent.error("not_running").jsonData()) as? [String: Any]
        #expect(error?["code"] as? String == "not_running")
    }

    @Test func clientMessagesDecode() throws {
        let decoder = RemoteJSON.decoder()
        #expect(try decoder.decode(ClientMessage.self, from: Data(#"{"type":"send.text","sessionId":"s","text":"merhaba"}"#.utf8))
                == .sendText(sessionId: "s", text: "merhaba"))
        #expect(try decoder.decode(ClientMessage.self, from: Data(#"{"type":"auth","token":"t"}"#.utf8)) == .auth(token: "t"))
        #expect(throws: DecodingError.self) {
            try decoder.decode(ClientMessage.self, from: Data(#"{"type":"rm -rf"}"#.utf8))
        }
    }
}
