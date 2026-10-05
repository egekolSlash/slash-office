import Foundation

/// Ofiste oda = depo (spec §3): ana klasör ve worktree'leri aynı odaya düşer. Ana thread'de çağrılmamalı.
public enum RepoIdentity {
    public struct Identity: Equatable, Sendable {
        /// Ana deponun klasörü; git deposu değilse (ya da git çalışmazsa) klasörün kendisi.
        public var roomKey: String
        /// Klasör ana deponun değil bir worktree'nin içindeyse worktree'nin adı.
        public var worktree: String?

        public init(roomKey: String, worktree: String?) {
            self.roomKey = roomKey
            self.worktree = worktree
        }
    }

    public static func locate(_ directory: String) -> Identity {
        guard FileManager.default.fileExists(atPath: directory) else { return Identity(roomKey: directory, worktree: nil) }
        let workspace = GitWorkspace(directory: directory)
        guard let common = workspace.commonDirectory() else { return Identity(roomKey: directory, worktree: nil) }
        let url = URL(fileURLWithPath: common)
        // Normal depo ve worktree'lerde ortak klasör `<ana depo>/.git`; çıplak depoda klasörün kendisi.
        guard url.lastPathComponent == ".git" else { return Identity(roomKey: directory, worktree: nil) }
        let roomKey = url.deletingLastPathComponent().path
        // Git gerçek yolları döndürür; çalışma ağacının kökü ana depodan farklıysa (depo içine yerleştirilmiş
        // `.claude/worktrees/x` dahil) bu bir worktree'dir.
        let top = workspace.topLevel()
        let worktree = top.flatMap { $0 == roomKey ? nil : ($0 as NSString).lastPathComponent }
        return Identity(roomKey: roomKey, worktree: worktree)
    }

    public static func roomKey(for directory: String) -> String { locate(directory).roomKey }
}
