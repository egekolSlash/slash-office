import Foundation

/// Codex CLI hook payload'ını (stdin JSON) ortak olaylara çevirir. Alanlar Claude'unkine çok yakın (`hook_event_name`,
/// `session_id`, `tool_name`, `tool_input`); kabuk komutları `Bash`, dosya düzenlemeleri `apply_patch`, plan `update_plan`.
public enum CodexNormalizer {
    public static func events(from payload: JSONValue) -> [AgentEvent] {
        switch payload["hook_event_name"]?.string {
        case "SessionStart":
            return [.sessionStarted(providerSessionID: payload["session_id"]?.string)]
        case "UserPromptSubmit":
            return [.promptSubmitted(text: payload["prompt"]?.string ?? "")]
        case "PreToolUse":
            let name = payload["tool_name"]?.string ?? "?"
            let input = payload["tool_input"]
            var events: [AgentEvent] = [.toolStarted(name: name, summary: summary(tool: name, input: input))]
            if name == "update_plan", let plan = input?["plan"]?.array {
                events.append(.todosChanged(plan.map(todoItem)))
            }
            // Kullanıcıya seçenekli soru (Plan modunda): cevap gelince PostToolUse ile çalışmaya döner.
            if name == "request_user_input" {
                events.append(.needsInput(.question(firstQuestion(in: input) ?? "")))
            }
            return events
        case "PostToolUse":
            let name = payload["tool_name"]?.string ?? "?"
            let files = name == "apply_patch" ? patchFiles(payload["tool_input"]?["command"]?.string ?? "") : []
            return [.toolFinished(name: name, touchedFiles: files)]
        case "PermissionRequest":
            let input = payload["tool_input"]
            let detail = input?["description"]?.string ?? input?["command"]?.string.map { String($0.prefix(80)) }
            return [.needsInput(.permission(detail ?? payload["tool_name"]?.string ?? ""))]
        case "Stop":
            return [.turnEnded]
        case "Interrupt":
            return [.interrupted]
        case "SessionEnd":
            return [.sessionEnded]
        default:
            return []
        }
    }

    static func summary(tool: String, input: JSONValue?) -> String? {
        guard let input else { return nil }
        if tool == "apply_patch" {
            return patchFiles(input["command"]?.string ?? "").first.map { ($0 as NSString).lastPathComponent }
        }
        return input["command"]?.string.map { String($0.prefix(40)) }
    }

    /// `update_plan` adımı: `{"step": "...", "status": "pending" | "in_progress" | "completed"}`.
    static func todoItem(_ value: JSONValue) -> TodoItem {
        TodoItem(title: value["step"]?.string ?? "", status: ClaudeNormalizer.todoStatus(value["status"]?.string) ?? .pending)
    }

    /// Soru aracının ilk sorusu: `questions[0].question` ya da düz `question`.
    static func firstQuestion(in input: JSONValue?) -> String? {
        input?["questions"]?.array?.first?["question"]?.string ?? input?["question"]?.string
    }

    /// apply_patch metnindeki dosyalar: `*** Add File: x`, `*** Update File: x`, `*** Delete File: x`, `*** Move to: y`.
    public static func patchFiles(_ patch: String) -> [String] {
        let markers = ["*** Add File: ", "*** Update File: ", "*** Delete File: ", "*** Move to: "]
        var files: [String] = []
        for line in patch.split(whereSeparator: \.isNewline) {
            guard let marker = markers.first(where: { line.hasPrefix($0) }) else { continue }
            let path = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            if !path.isEmpty, !files.contains(path) { files.append(path) }
        }
        return files
    }
}
