import Foundation

/// Antigravity CLI (`agy`) hook payload'ı: anahtarlar camelCase (`hookEventName`, `conversationId`, `toolCall`).
/// Kullanıcı isteğinin hook'u yok; tur, modelin ilk çağrısından (`PreInvocation`, `invocationNum` 0) başlar.
/// Sorular `ask_question` aracından anlaşılır; izin bildirimi yok, izin bekleyen oturum "çalışıyor" görünür.
public enum AntigravityNormalizer {
    public static func events(from payload: JSONValue) -> [AgentEvent] {
        switch payload["hookEventName"]?.string {
        case "SessionStart":
            return [.sessionStarted(providerSessionID: payload["conversationId"]?.string)]
        case "PreInvocation":
            guard case .number(let number)? = payload["invocationNum"], number == 0 else { return [] }
            return [.promptSubmitted(text: payload["lastUserInput"]?.string ?? "")]
        case "PreToolUse":
            let name = payload["toolCall"]?["name"]?.string ?? "?"
            let args = payload["toolCall"]?["args"]
            var events: [AgentEvent] = [.toolStarted(name: name, summary: summary(args))]
            // Kullanıcıya soru: cevap gelince PostToolUse ile çalışmaya döner.
            if name == "ask_question" {
                events.append(.needsInput(.question(CodexNormalizer.firstQuestion(in: args) ?? "")))
            }
            return events
        case "PostToolUse":
            let name = payload["toolCall"]?["name"]?.string ?? "?"
            let path = writes(name) ? filePath(payload["toolCall"]?["args"]) : nil
            return [.toolFinished(name: name, touchedFiles: path.map { [$0] } ?? [])]
        case "Stop":
            return payload["terminationReason"]?.string == "USER_CANCELED" ? [.interrupted] : [.turnEnded]
        default:
            return []
        }
    }

    /// Dosya yazan araçlar (`write_file`, `edit_file`, `replace_file_content`…).
    static func writes(_ tool: String) -> Bool {
        ["write", "edit", "replace"].contains { tool.contains($0) }
    }

    static func filePath(_ args: JSONValue?) -> String? {
        (args?["Path"] ?? args?["TargetFile"] ?? args?["AbsolutePath"])?.string.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func summary(_ args: JSONValue?) -> String? {
        if let path = filePath(args) { return (path as NSString).lastPathComponent }
        return args?["CommandLine"]?.string.map { String($0.prefix(40)) }
    }
}
