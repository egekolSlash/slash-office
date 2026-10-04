import Foundation

/// Claude Code hook payload'ını (stdin JSON) ortak olaylara çevirir.
public enum ClaudeNormalizer {
    public static func events(from payload: JSONValue) -> [AgentEvent] {
        switch payload["hook_event_name"]?.string {
        case "SessionStart":
            return [.sessionStarted(providerSessionID: payload["session_id"]?.string)]
        case "UserPromptSubmit":
            return [.promptSubmitted(text: payload["prompt"]?.string ?? "")]
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
            return events
        case "PostToolUse":
            let name = payload["tool_name"]?.string ?? "?"
            let path = payload["tool_input"]?["file_path"]?.string
            return [.toolFinished(name: name, touchedFiles: path.map { [$0] } ?? [])]
        case "Notification":
            let message = payload["message"]?.string ?? ""
            let type = payload["notification_type"]?.string
            if type == "idle_prompt" { return [.inputIdle] }
            let isPermission = type == "permission_prompt"
                || (type == nil && message.localizedCaseInsensitiveContains("permission"))
            return isPermission ? [.needsInput(.permission(message))] : []
        case "Stop":
            return [.turnEnded]
        case "SessionEnd":
            // /clear ve /resume sırasında da gelir ama süreç çalışmaya devam eder; ardından yeni bir SessionStart gelir.
            let reason = payload["reason"]?.string
            return reason == "clear" || reason == "resume" ? [] : [.sessionEnded]
        default:
            return []
        }
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
        let status: TodoItem.Status = switch value["status"]?.string {
        case "completed": .done
        case "in_progress": .inProgress
        default: .pending
        }
        return TodoItem(title: value["content"]?.string ?? "", status: status)
    }
}
