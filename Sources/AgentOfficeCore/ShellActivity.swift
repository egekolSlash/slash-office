import Darwin

/// Shell oturumunun ne yaptığı: terminalin ön plan süreç grubu shell'in kendisiyse boşta,
/// başka bir grupsa (ör. `npm run dev`) o komut çalışıyor.
public enum ShellActivity {
    public static func state(shellPID: Int32, foregroundGroup: Int32?, commandName: String?) -> AgentState {
        guard let group = foregroundGroup, group != shellPID else { return .idle }
        return .working(tool: commandName)
    }

    /// PTY'nin ön plan süreç grubu; okunamazsa nil.
    public static func foregroundGroup(ptyFD: Int32) -> Int32? {
        guard ptyFD >= 0 else { return nil }
        let group = tcgetpgrp(ptyFD)
        return group > 0 ? group : nil
    }

    public static func processName(_ pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let name = String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return displayName(name, executablePath: executablePath(pid))
    }

    /// Claude'un yerel kurulumu `~/.local/share/claude/versions/2.1.289` gibi bir dosyadır; süreç adı sürüm
    /// numarası olur. Böyle süreçler "claude" olarak gösterilir.
    public static func displayName(_ name: String, executablePath: String?) -> String {
        if let path = executablePath, path.contains("/claude/versions/") { return "claude" }
        return name
    }

    /// Sürecin çalışma klasörü (shell'de `cd` ile değişir); okunamazsa nil.
    public static func workingDirectory(_ pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
