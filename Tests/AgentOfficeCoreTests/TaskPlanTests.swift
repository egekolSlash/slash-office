import Foundation
import Testing
@testable import AgentOfficeCore

/// Claude'un adım adım planı: görev araçlarının hook olayları, store'daki liste ve diskteki görev dosyaları.
@MainActor
@Suite struct TaskPlanTests {
    // MARK: Normalizer (gerçek Claude Code 2.1 hook çıktısından)

    @Test func taskCreatedHookAddsStep() {
        let events = ClaudeNormalizer.events(from: json(#"{"hook_event_name":"TaskCreated","task_id":"1","task_subject":"Write tests","task_description":"d"}"#))
        #expect(events == [.taskCreated(id: "1", title: "Write tests")])
    }

    @Test func taskUpdateChangesStatusTitleOrDeletes() {
        func post(_ input: String) -> [AgentEvent] {
            ClaudeNormalizer.events(from: json(#"{"hook_event_name":"PostToolUse","tool_name":"TaskUpdate","tool_input":\#(input)}"#))
        }
        #expect(post(#"{"taskId":"1","status":"in_progress"}"#).last == .taskUpdated(id: "1", status: .inProgress, title: nil))
        #expect(post(#"{"taskId":"1","status":"completed"}"#).last == .taskUpdated(id: "1", status: .done, title: nil))
        #expect(post(#"{"taskId":"2","subject":"Renamed"}"#).last == .taskUpdated(id: "2", status: nil, title: "Renamed"))
        #expect(post(#"{"taskId":"3","status":"deleted"}"#).last == .taskDeleted(id: "3"))
        // Sadece bağımlılık değişti: plan için olay yok.
        #expect(post(#"{"taskId":"1","addBlocks":["2"]}"#) == [.toolFinished(name: "TaskUpdate", touchedFiles: [])])
    }

    @Test func subagentStepUpdateDoesNotChangeState() {
        let events = ClaudeNormalizer.events(from: json(#"{"hook_event_name":"PostToolUse","agent_id":"x","tool_name":"TaskUpdate","tool_input":{"taskId":"4","status":"completed"}}"#))
        #expect(events == [.taskUpdated(id: "4", status: .done, title: nil)])
    }

    @Test func exitPlanModeProposesPlan() {
        let events = ClaudeNormalizer.events(from: json(#"{"hook_event_name":"PreToolUse","tool_name":"ExitPlanMode","tool_input":{"plan":"1. A\n2. B"}}"#))
        #expect(events.last == .planProposed("1. A\n2. B"))
    }

    @Test func taskEventsDoNotChangeState() {
        for event: AgentEvent in [.taskCreated(id: "1", title: "a"), .taskUpdated(id: "1", status: .done, title: nil),
                                  .taskDeleted(id: "1"), .planProposed("p")] {
            #expect(AgentStateMachine.reduce(.working(tool: "X"), event) == .working(tool: "X"))
        }
    }

    /// Claude Code 2.1.328'den kaydedilmiş gerçek akış (a, b, c oluşturulur; a başlar ve biter; c silinir). Hook
    /// istemcisinden geçtiği gibi (`tool_response` atılmış) okunur.
    @Test func recordedFlowBuildsPlan() throws {
        let url = try #require(Bundle.module.url(forResource: "hooks-tasks", withExtension: "jsonl", subdirectory: "Fixtures"))
        let store = store()
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            let envelope = try #require(HookEnvelope.encodeLine(session: "s", provider: "claude", rawPayload: Data(line.utf8)))
            let payload = try JSONDecoder().decode(HookEnvelope.self, from: envelope).payload
            store.apply(ClaudeNormalizer.events(from: payload), to: "s")
        }
        #expect(store.session("s")?.todos == [TodoItem(id: "1", title: "a", status: .done), TodoItem(id: "2", title: "b", status: .pending)])
    }

    // MARK: Store

    private func store() -> AgentStore {
        let store = AgentStore()
        store.register(id: "s", title: "s", cwd: "/s")
        return store
    }

    @Test func stepsAreCreatedUpdatedAndDeleted() {
        let store = store()
        store.apply([.taskCreated(id: "1", title: "a"), .taskCreated(id: "2", title: "b"), .taskCreated(id: "3", title: "c"),
                     .taskUpdated(id: "1", status: .inProgress, title: nil), .taskUpdated(id: "1", status: .done, title: nil),
                     .taskUpdated(id: "2", status: nil, title: "b2"), .taskDeleted(id: "3"),
                     .taskUpdated(id: "ghost", status: .done, title: nil)], to: "s")
        #expect(store.session("s")?.todos == [TodoItem(id: "1", title: "a", status: .done), TodoItem(id: "2", title: "b2", status: .pending)])
    }

    @Test func newStepAfterFinishedPlanStartsNewPlan() {
        let store = store()
        store.apply([.taskCreated(id: "1", title: "a"), .taskCreated(id: "2", title: "b")], to: "s")
        store.apply([.taskUpdated(id: "1", status: .done, title: nil)], to: "s")
        store.apply([.taskCreated(id: "3", title: "c")], to: "s")
        #expect(store.session("s")?.todos.map(\.id) == ["1", "2", "3"])
        store.apply([.taskUpdated(id: "2", status: .done, title: nil), .taskUpdated(id: "3", status: .done, title: nil)], to: "s")
        store.apply([.taskCreated(id: "4", title: "next")], to: "s")
        #expect(store.session("s")?.todos == [TodoItem(id: "4", title: "next", status: .pending)])
    }

    @Test func clearStartsOverButResumeKeepsPlan() {
        let store = store()
        store.apply([.sessionStarted(providerSessionID: "c1"), .taskCreated(id: "1", title: "a"), .planProposed("p")], to: "s")
        store.apply([.sessionStarted(providerSessionID: "c1")], to: "s")
        #expect(store.session("s")?.todos.count == 1)
        #expect(store.session("s")?.plan == "p")
        store.apply([.sessionStarted(providerSessionID: "c2")], to: "s")
        #expect(store.session("s")?.todos == [])
        #expect(store.session("s")?.plan == nil)
    }

    @Test func restoreFillsEmptyOrStaleListOnly() {
        let store = store()
        let disk = [TodoItem(id: "1", title: "a", status: .done), TodoItem(id: "2", title: "b", status: .inProgress)]
        store.restoreTodos(disk, for: "s")
        #expect(store.session("s")?.todos == disk)
        // Hook'larla gelen daha yeni durum, aynı adımları içeren eski bir okumayla ezilmez.
        store.apply([.taskUpdated(id: "2", status: .done, title: nil)], to: "s")
        store.restoreTodos(disk, for: "s")
        #expect(store.session("s")?.todos.last?.status == .done)
        // Diskte bilinmeyen bir adım varsa (uygulama kapalıyken eklendi) liste diskten gelir.
        let newer = disk + [TodoItem(id: "3", title: "c", status: .pending)]
        store.restoreTodos(newer, for: "s")
        #expect(store.session("s")?.todos == newer)
        // TodoWrite listesine dokunulmaz.
        store.apply([.todosChanged([TodoItem(title: "w", status: .pending)])], to: "s")
        store.restoreTodos(newer, for: "s")
        #expect(store.session("s")?.todos == [TodoItem(title: "w", status: .pending)])
    }

    // MARK: Görev dosyaları

    @Test func taskFilesLoadInIDOrder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tasks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func write(_ name: String, _ text: String) throws { try Data(text.utf8).write(to: dir.appendingPathComponent(name)) }
        try write("10.json", #"{"id":"10","subject":"ten","status":"pending","blocks":[],"blockedBy":[]}"#)
        try write("2.json", #"{"id":"2","subject":"two","description":"d","status":"completed","blocks":[],"blockedBy":[]}"#)
        try write("3.json", #"{"id":"3","subject":"gone","status":"deleted"}"#)
        try write("4.json", "not json")
        try write(".highwatermark", "10")
        try write(".lock", "")
        #expect(ClaudeTaskFiles.load(dir) == [TodoItem(id: "2", title: "two", status: .done), TodoItem(id: "10", title: "ten", status: .pending)])
        #expect(ClaudeTaskFiles.load(dir.appendingPathComponent("missing")) == [])
    }

    @Test func taskDirectoryFollowsConfigDir() {
        #expect(ClaudeTaskFiles.directory(claudeSessionID: "abc", environment: [:], home: "/Users/me").path == "/Users/me/.claude/tasks/abc")
        #expect(ClaudeTaskFiles.directory(claudeSessionID: "abc", environment: ["CLAUDE_CONFIG_DIR": "/cfg"], home: "/Users/me").path == "/cfg/tasks/abc")
    }

    @Test func shellWrapperEnablesTaskToolsUnlessUserSetIt() {
        #expect(ShellIntegration.wrapperScript.contains(#"export CLAUDE_CODE_ENABLE_TODO_TOOLS="${CLAUDE_CODE_ENABLE_TODO_TOOLS:-1}""#))
    }
}
