import Foundation

/// Ofiste oda = depo (spec §3): ana klasör ve worktree'leri aynı odaya düşer. Ana thread'de çağrılmamalı.
public enum RepoIdentity {
    /// Odanın anahtarı: ana deponun klasörü; git deposu değilse (ya da git çalışmazsa) klasörün kendisi.
    public static func roomKey(for directory: String) -> String {
        guard FileManager.default.fileExists(atPath: directory),
              let common = GitWorkspace(directory: directory).commonDirectory() else { return directory }
        let url = URL(fileURLWithPath: common)
        // Normal depo ve worktree'lerde ortak klasör `<ana depo>/.git`; çıplak depoda klasörün kendisi.
        return url.lastPathComponent == ".git" ? url.deletingLastPathComponent().path : directory
    }

    /// Klasör ana deponun kendisi ya da içindeki bir alt klasör değilse worktree'dir; adı klasör adıdır.
    public static func worktreeName(directory: String, roomKey: String) -> String? {
        directory == roomKey || directory.hasPrefix(roomKey + "/") ? nil : (directory as NSString).lastPathComponent
    }
}
