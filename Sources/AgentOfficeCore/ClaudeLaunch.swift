import Foundation

public struct LaunchCommand: Equatable, Sendable {
    public var executable: String
    public var args: [String]
    public var environment: [String: String]
    public var currentDirectory: String

    public var environmentList: [String] {
        environment.map { "\($0.key)=\($0.value)" }.sorted()
    }
}

public enum ClaudeLaunch {
    public static let hookEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"]

    /// `--settings` ile verilen, sadece bu oturuma hook ekleyen ayar dosyası.
    public static func settingsJSON(hookCommand: String) -> Data {
        var hooks: [String: JSONValue] = [:]
        for event in hookEvents {
            var entry: [String: JSONValue] = [
                "hooks": .array([.object([
                    "type": .string("command"),
                    "command": .string(hookCommand),
                    "timeout": .number(5),
                ])]),
            ]
            if event == "PreToolUse" || event == "PostToolUse" { entry["matcher"] = .string("*") }
            hooks[event] = .array([.object(entry)])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try! encoder.encode(JSONValue.object(["hooks": .object(hooks)]))
    }

    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    public static func command(claudePath: String, sessionID: String, resume: Bool, settingsPath: String,
                               cwd: String, socketPath: String, baseEnvironment: [String: String],
                               tag: String? = nil) -> LaunchCommand {
        let flag = resume ? "--resume" : "--session-id"
        let script = "exec \(shellQuote(claudePath)) \(flag) \(shellQuote(sessionID)) --settings \(shellQuote(settingsPath))"
        // Uygulama bir Claude oturumunun içinden başlatıldıysa onun değişkenleri ajana geçmesin.
        var environment = baseEnvironment.filter { key, _ in
            key != "CLAUDECODE" && !key.hasPrefix("CLAUDE_CODE_") && !key.hasPrefix("AGENT_OFFICE_")
        }
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["AGENT_OFFICE_SESSION"] = tag ?? sessionID
        environment["AGENT_OFFICE_SOCKET"] = socketPath
        return LaunchCommand(executable: "/bin/zsh", args: ["-l", "-c", script], environment: environment, currentDirectory: cwd)
    }
}
