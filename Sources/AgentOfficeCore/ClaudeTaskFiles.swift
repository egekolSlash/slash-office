import Foundation

/// Claude Code'un görev listesi diskte: `~/.claude/tasks/<oturum kimliği>/<görev kimliği>.json`. Hook'lar adımları
/// tek tek bildirir; uygulama yeniden açıldığında ya da kaçırılmış bir adım güncellenince liste buradan okunur.
public enum ClaudeTaskFiles {
    public static func directory(claudeSessionID: String, environment: [String: String] = ProcessInfo.processInfo.environment,
                                 home: String = NSHomeDirectory()) -> URL {
        let config = environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.claude"
        return URL(fileURLWithPath: config, isDirectory: true)
            .appendingPathComponent("tasks", isDirectory: true)
            .appendingPathComponent(claudeSessionID, isDirectory: true)
    }

    /// Adımlar kimlik sırasıyla (sayısal); okunamayan ve silinmiş adımlar atlanır. Klasör yoksa boş.
    public static func load(_ directory: URL, fileManager: FileManager = .default) -> [TodoItem] {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles]) else { return [] }
        let items: [TodoItem] = files.filter { $0.pathExtension == "json" }.compactMap { file in
            guard let data = try? Data(contentsOf: file),
                  let value = try? JSONDecoder().decode(JSONValue.self, from: data),
                  let id = value["id"]?.string, let subject = value["subject"]?.string,
                  value["status"]?.string != "deleted" else { return nil }
            return TodoItem(id: id, title: subject, status: ClaudeNormalizer.todoStatus(value["status"]?.string) ?? .pending)
        }
        return items.sorted { ($0.id ?? "").localizedStandardCompare($1.id ?? "") == .orderedAscending }
    }
}
