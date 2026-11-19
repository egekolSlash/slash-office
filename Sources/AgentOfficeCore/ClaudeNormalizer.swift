import Foundation

/// Claude Code hook payload'ını (stdin JSON) ortak olaylara çevirir.
public enum ClaudeNormalizer {
    /// Oturumun kayıt dosyası (ai-title buradan okunur); her hook olayında gelir.
    public static func transcriptPath(from payload: JSONValue) -> String? {
        payload["transcript_path"]?.string.flatMap { $0.isEmpty ? nil : $0 }
    }

    public static func events(from payload: JSONValue) -> [AgentEvent] {
        switch payload["hook_event_name"]?.string {
        case "SessionStart":
            return [.sessionStarted(providerSessionID: payload["session_id"]?.string)]
        case "UserPromptSubmit":
            let prompt = payload["prompt"]?.string ?? ""
            if let id = taskNotificationID(prompt) { return [.backgroundFinished(id: id), .promptSubmitted(text: "")] }
            return [.promptSubmitted(text: prompt)]
        case "PreToolUse" where payload["agent_id"] != nil:
            return []
        case "PostToolUse" where payload["agent_id"] != nil:
            // Subagent'lar oturumun görev listesini paylaşır: adım güncellemesi ana oturumun planına işlenir.
            if payload["tool_name"]?.string == "TaskUpdate" { return taskUpdate(payload["tool_input"]).map { [$0] } ?? [] }
            let path = payload["tool_input"]?["file_path"]?.string
            return path.map { [.filesTouched([$0])] } ?? []
        case "PreToolUse":
            let name = payload["tool_name"]?.string ?? "?"
            let input = payload["tool_input"]
            var events: [AgentEvent] = [.toolStarted(name: name, summary: summary(of: input))]
            if name == "AskUserQuestion" {
                let question = input?["questions"]?.array?.first?["question"]?.string ?? ""
                events.append(.needsInput(.question(question)))
            }
            if name == "TodoWrite", let todos = input?["todos"]?.array {
                events.append(.todosChanged(todos.map(todoItem)))
            }
            if name == "ExitPlanMode", let plan = input?["plan"]?.string, !plan.isEmpty {
                events.append(.planProposed(plan))
            }
            return events
        case "PostToolUse":
            let name = payload["tool_name"]?.string ?? "?"
            let path = payload["tool_input"]?["file_path"]?.string
            var events: [AgentEvent] = [.toolFinished(name: name, touchedFiles: path.map { [$0] } ?? [])]
            if let task = backgroundTask(tool: name, input: payload["tool_input"], response: payload["tool_response"]) {
                events.insert(.backgroundStarted(task), at: 0)
            }
            // Sadece başarılı güncelleme PostToolUse'a gelir; yeni adım TaskCreated ile gelir (kimliği orada).
            if name == "TaskUpdate", let update = taskUpdate(payload["tool_input"]) { events.append(update) }
            return events
        case "TaskCreated":
            guard let id = payload["task_id"]?.string, let subject = payload["task_subject"]?.string else { return [] }
            return [.taskCreated(id: id, title: subject)]
        case "Notification":
            let message = payload["message"]?.string ?? ""
            let type = payload["notification_type"]?.string
            if type == "idle_prompt" { return [.inputIdle] }
            let isPermission = type == "permission_prompt"
                || (type == nil && message.localizedCaseInsensitiveContains("permission"))
            return isPermission ? [.needsInput(.permission(message))] : []
        case "Stop":
            // Liste tur bitmeden güncellenir: "bitti" kararı arka planda iş kalıp kalmadığına bakar.
            guard let tasks = payload["background_tasks"]?.array else { return [.turnEnded] }
            return [.backgroundSnapshot(tasks.compactMap(snapshotTask)), .turnEnded]
        case "SessionEnd":
            // /clear ve /resume sırasında da gelir ama süreç çalışmaya devam eder; ardından yeni bir SessionStart gelir.
            let reason = payload["reason"]?.string
            return reason == "clear" || reason == "resume" ? [] : [.sessionEnded]
        default:
            return []
        }
    }

    /// `<task-notification><task-id>ID</task-id>…`: Claude'a arka plan işinin bittiğini bildiren prompt.
    static func taskNotificationID(_ prompt: String) -> String? {
        guard prompt.hasPrefix("<task-notification>"),
              let start = prompt.range(of: "<task-id>"), let end = prompt.range(of: "</task-id>"),
              start.upperBound <= end.lowerBound else { return nil }
        let id = prompt[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    static func backgroundTask(tool: String, input: JSONValue?, response: JSONValue?) -> BackgroundJob? {
        switch tool {
        case "Bash":
            guard input?["run_in_background"]?.bool == true, let id = response?["backgroundTaskId"]?.string else { return nil }
            return BackgroundJob(id: id, kind: .shell, label: input?["description"]?.string ?? input?["command"]?.string ?? "")
        case "Agent", "Task":
            guard response?["status"]?.string == "async_launched", let id = response?["agentId"]?.string else { return nil }
            return BackgroundJob(id: id, kind: .subagent, label: input?["description"]?.string ?? "")
        default:
            return nil
        }
    }

    static func snapshotTask(_ value: JSONValue) -> BackgroundJob? {
        guard value["status"]?.string == "running", let id = value["id"]?.string else { return nil }
        let kind: BackgroundJob.Kind = value["type"]?.string == "shell" ? .shell : .subagent
        return BackgroundJob(id: id, kind: kind, label: value["description"]?.string ?? value["command"]?.string ?? "")
    }

    static func summary(of input: JSONValue?) -> String? {
        guard let input else { return nil }
        if let path = input["file_path"]?.string ?? input["notebook_path"]?.string {
            return (path as NSString).lastPathComponent
        }
        if let text = input["command"]?.string ?? input["pattern"]?.string {
            return String(text.prefix(40))
        }
        return nil
    }

    static func todoItem(_ value: JSONValue) -> TodoItem {
        TodoItem(title: value["content"]?.string ?? "", status: todoStatus(value["status"]?.string) ?? .pending)
    }

    static func todoStatus(_ value: String?) -> TodoItem.Status? {
        switch value {
        case "completed": .done
        case "in_progress": .inProgress
        case "pending": .pending
        default: nil
        }
    }

    /// TaskUpdate girdisi: `taskId`, isteğe bağlı `status` (pending / in_progress / completed / deleted) ve `subject`.
    static func taskUpdate(_ input: JSONValue?) -> AgentEvent? {
        guard let id = input?["taskId"]?.string else { return nil }
        let status = input?["status"]?.string
        if status == "deleted" { return .taskDeleted(id: id) }
        let subject = input?["subject"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        let mapped = todoStatus(status)
        guard mapped != nil || subject != nil else { return nil }
        return .taskUpdated(id: id, status: mapped, title: subject)
    }
}
