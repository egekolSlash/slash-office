import Foundation
import Testing
@testable import AgentOfficeCore

/// Claude Code 2.1.309'dan kaydedilmiş gerçek akış: arka plan Bash + arka plan subagent, tur biter, ikisi sırayla biter.
@MainActor
@Suite struct BackgroundTasksTests {
    func recordedPayloads() throws -> [JSONValue] {
        let url = try #require(Bundle.module.url(forResource: "hooks-background", withExtension: "jsonl", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
            try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8))
        }
    }

    @Test func normalizerReadsStartsSnapshotsAndNotifications() throws {
        let events = try recordedPayloads().flatMap(ClaudeNormalizer.events(from:))
        #expect(events.contains(.backgroundStarted(BackgroundJob(id: "brlu73wf7", kind: .shell, label: "Sleep 20 seconds then echo done"))))
        #expect(events.contains(.backgroundStarted(BackgroundJob(id: "ae12137e659ffef4a", kind: .subagent, label: "Sleep 15 and reply ok"))))
        #expect(events.contains(.backgroundSnapshot([
            BackgroundJob(id: "brlu73wf7", kind: .shell, label: "Sleep 20 seconds then echo done"),
            BackgroundJob(id: "ae12137e659ffef4a", kind: .subagent, label: "Sleep 15 and reply ok"),
        ])))
        #expect(events.contains(.backgroundFinished(id: "ae12137e659ffef4a")))
        #expect(events.contains(.backgroundFinished(id: "brlu73wf7")))
    }

    @Test func recordedFlowKeepsTasksUntilNotificationsAndNotifiesOnlyAtTheEnd() throws {
        let store = AgentStore()
        store.register(id: "a", title: "A", cwd: "/a")
        var finishedAt: [Int] = []
        for (i, payload) in try recordedPayloads().enumerated() {
            let previous = store.session("a")?.state
            let events = ClaudeNormalizer.events(from: payload)
            store.apply(events, to: "a", watched: false)
            let after = store.session("a")
            if NotificationPolicy.finished(previous: previous, events: events, current: after?.state,
                                           background: after?.backgroundTasks.count ?? 0) {
                finishedAt.append(i)
            }
            if payload["hook_event_name"]?.string == "Stop", payload["last_assistant_message"]?.string == "waiting" {
                #expect(after?.state == .idle)
                #expect(after?.backgroundTasks.map(\.id) == ["brlu73wf7", "ae12137e659ffef4a"])
                #expect(after?.unseenFinish == false)
            }
        }
        let session = try #require(store.session("a"))
        #expect(session.backgroundTasks.isEmpty)
        // Kullanıcının ilk isteği kalır; bildirim prompt'ları son istek olmaz.
        #expect(session.lastPrompt?.hasPrefix("Do exactly this") == true)
        // İlk Stop (işler sürerken) bildirmez; sonraki iki tur (bildirimleri işleyen turlar) iş kalmadığı için bildirir.
        #expect(finishedAt.count == 2)
        #expect(session.state == .exited)
    }

    @Test func subagentToolEventsDoNotChangeMainState() {
        let payload = json(#"{"hook_event_name":"PreToolUse","agent_id":"x","tool_name":"Bash","tool_input":{"command":"sleep 1"}}"#)
        #expect(ClaudeNormalizer.events(from: payload) == [])
        let post = json(#"{"hook_event_name":"PostToolUse","agent_id":"x","tool_name":"Write","tool_input":{"file_path":"/p/f.txt"},"tool_response":{}}"#)
        #expect(ClaudeNormalizer.events(from: post) == [.filesTouched(["/p/f.txt"])])

        let store = AgentStore()
        store.register(id: "a", title: "A", cwd: "/a")
        store.apply([.sessionStarted(providerSessionID: nil), .turnEnded], to: "a")
        store.apply([.filesTouched(["/p/f.txt"])], to: "a")
        #expect(store.session("a")?.state == .idle)
        #expect(store.session("a")?.touchedFiles == ["/p/f.txt"])
    }

    @Test func snapshotKeepsOnlyRunningTasksAndMissingFieldKeepsList() {
        let stop = json(#"{"hook_event_name":"Stop","background_tasks":[{"id":"a","type":"shell","status":"running","command":"npm test"},{"id":"b","type":"subagent","status":"completed","description":"x"}]}"#)
        #expect(ClaudeNormalizer.events(from: stop) == [.backgroundSnapshot([BackgroundJob(id: "a", kind: .shell, label: "npm test")]), .turnEnded])
        #expect(ClaudeNormalizer.events(from: json(#"{"hook_event_name":"Stop"}"#)) == [.turnEnded])
    }

    @Test func foregroundBashAndSyncAgentAreNotBackground() {
        let bash = json(#"{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"stdout":""}}"#)
        #expect(ClaudeNormalizer.events(from: bash) == [.toolFinished(name: "Bash", touchedFiles: [])])
        let agent = json(#"{"hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"description":"d"},"tool_response":{"status":"completed"}}"#)
        #expect(ClaudeNormalizer.events(from: agent) == [.toolFinished(name: "Agent", touchedFiles: [])])
    }

    @Test func sessionEndClearsAndInterruptKeepsTasks() {
        let store = AgentStore()
        store.register(id: "a", title: "A", cwd: "/a")
        let task = BackgroundJob(id: "t", kind: .shell, label: "x")
        store.apply([.promptSubmitted(text: "go"), .backgroundStarted(task), .interrupted], to: "a")
        #expect(store.session("a")?.backgroundTasks == [task])
        store.apply([.sessionEnded], to: "a")
        #expect(store.session("a")?.backgroundTasks == [])
    }
}
