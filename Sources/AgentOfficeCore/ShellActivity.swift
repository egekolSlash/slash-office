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
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
