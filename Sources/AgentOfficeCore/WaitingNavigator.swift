/// ⌘J: odaktaki oturumdan sonra gelen ilk bekleyen oturum, sona gelince başa döner (spec §4).
public enum WaitingNavigator {
    public static func next(after current: String?, ids: [String], isWaiting: (String) -> Bool) -> String? {
        guard !ids.isEmpty else { return nil }
        let start = current.flatMap { ids.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        for offset in 0..<ids.count {
            let id = ids[(start + offset) % ids.count]
            if isWaiting(id) { return id }
        }
        return nil
    }
}
