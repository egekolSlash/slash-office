import Foundation

/// Düz terminal oturumu: kullanıcının login shell'i. Entegrasyon verilirse terminalde elle açılan `claude`
/// da bu oturumun hook'larıyla başlar, böylece durumu (çalışıyor, soru soruyor…) görünür.
public enum ShellLaunch {
    public static func command(shellPath: String, cwd: String, sessionID: String,
                               baseEnvironment: [String: String], integration: ShellIntegration? = nil) -> LaunchCommand {
        var environment = LaunchEnvironment.prepare(baseEnvironment, sessionID: sessionID,
                                                    socketPath: integration?.socketPath)
        if let integration {
            environment["AGENT_OFFICE_REAL_CLAUDE"] = integration.claudePath
            environment["AGENT_OFFICE_CLAUDE_SETTINGS"] = integration.settingsPath
            environment["AGENT_OFFICE_BIN"] = integration.binDirectory
            environment["PATH"] = integration.binDirectory + (environment["PATH"].map { ":" + $0 } ?? "")
            // zsh: kullanıcının dosyaları yüklendikten sonra PATH'in başına sarmalayıcı yeniden eklenir.
            if (shellPath as NSString).lastPathComponent == "zsh" {
                environment["AGENT_OFFICE_USER_ZDOTDIR"] = baseEnvironment["ZDOTDIR"] ?? baseEnvironment["HOME"] ?? NSHomeDirectory()
                environment["AGENT_OFFICE_ZDOTDIR"] = integration.zdotDirectory
                environment["ZDOTDIR"] = integration.zdotDirectory
            }
        }
        return LaunchCommand(executable: shellPath, args: ["-l"], environment: environment, currentDirectory: cwd)
    }
}

/// Terminaldeki `claude` sarmalayıcısı ve zsh başlangıç dosyaları.
public struct ShellIntegration: Equatable, Sendable {
    public var binDirectory: String
    public var zdotDirectory: String
    public var claudePath: String
    public var settingsPath: String
    public var socketPath: String

    public init(binDirectory: String, zdotDirectory: String, claudePath: String, settingsPath: String, socketPath: String) {
        self.binDirectory = binDirectory
        self.zdotDirectory = zdotDirectory
        self.claudePath = claudePath
        self.settingsPath = settingsPath
        self.socketPath = socketPath
    }

    public static let wrapperScript = """
    #!/bin/sh
    # Agent Office: starts claude, opened in the terminal, with this session's hook settings.
    real="$AGENT_OFFICE_REAL_CLAUDE"
    if [ ! -x "$real" ]; then
        echo "agent-office: claude not found ($real)" >&2
        exit 127
    fi
    if [ -n "$AGENT_OFFICE_CLAUDE_SETTINGS" ] && [ -f "$AGENT_OFFICE_CLAUDE_SETTINGS" ]; then
        exec "$real" --settings "$AGENT_OFFICE_CLAUDE_SETTINGS" "$@"
    fi
    exec "$real" "$@"

    """

    /// Her dosya kullanıcının aynı adlı dosyasını kendi ZDOTDIR'iyle yükler. `.zshrc` ve `.zlogin` sonunda
    /// sarmalayıcı PATH'in başına geri konur; `.zlogin` ZDOTDIR'i kullanıcınınkine bırakır (iç içe shell'ler normal).
    public static func zshFiles() -> [String: String] {
        func source(_ name: String) -> String {
            """
            if [ -f "$__ao_user_zdotdir/\(name)" ]; then
                ZDOTDIR="$__ao_user_zdotdir"
                source "$__ao_user_zdotdir/\(name)"
                __ao_user_zdotdir="$ZDOTDIR"
                ZDOTDIR="$AGENT_OFFICE_ZDOTDIR"
            fi
            """
        }
        let prependPath = #"[ -n "$AGENT_OFFICE_BIN" ] && path=("$AGENT_OFFICE_BIN" ${path:#$AGENT_OFFICE_BIN})"#
        return [
            ".zshenv": "# Agent Office shell entegrasyonu\n__ao_user_zdotdir=\"${AGENT_OFFICE_USER_ZDOTDIR:-$HOME}\"\n" + source(".zshenv") + "\n",
            ".zprofile": source(".zprofile") + "\n",
            // macOS'un /etc/zshrc'si HISTFILE'ı ZDOTDIR'e göre (bizim klasöre) ayarlar; kullanıcınınkine çevrilir.
            ".zshrc": #"[ "$HISTFILE" = "$AGENT_OFFICE_ZDOTDIR/.zsh_history" ] && HISTFILE="$__ao_user_zdotdir/.zsh_history""#
                + "\n" + source(".zshrc") + "\n" + prependPath + "\n",
            ".zlogin": source(".zlogin") + "\n" + prependPath + "\nZDOTDIR=\"$__ao_user_zdotdir\"\nunset __ao_user_zdotdir\n",
        ]
    }

    /// Sarmalayıcıyı ve zsh dosyalarını diske yazar (her açılışta güncellenir).
    public func install() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: binDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: zdotDirectory, withIntermediateDirectories: true)
        let wrapper = binDirectory + "/claude"
        try Self.wrapperScript.write(toFile: wrapper, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper)
        for (name, content) in Self.zshFiles() {
            try content.write(toFile: zdotDirectory + "/" + name, atomically: true, encoding: .utf8)
        }
    }
}
