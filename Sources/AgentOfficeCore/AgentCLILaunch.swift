import Foundation

/// Claude dışındaki ajan CLI'ları. Gemini seçeneği Gemini CLI'ın yerini alan Antigravity CLI'ı (`agy`) açar; o yoksa
/// eski `gemini` komutunu (hook'suz) dener.
public enum AgentCLI: String, Sendable, CaseIterable {
    case codex
    case antigravity = "agy"
    case gemini

    /// Komut adı (PATH'te aranır).
    public var executableName: String { rawValue }

    /// Hook yardımcısına verilen sağlayıcı adı (`agent-office-hook <provider>`); hook'u olmayanlarda nil.
    public var hookProvider: String? {
        switch self {
        case .codex: "codex"
        case .antigravity: "antigravity"
        case .gemini: nil
        }
    }

    /// Oturum türü için denenecek CLI'lar, öncelik sırasıyla.
    public static func candidates(for kind: SessionKind) -> [AgentCLI] {
        switch kind {
        case .codex: [.codex]
        case .gemini: [.antigravity, .gemini]
        case .claude, .shell: []
        }
    }

    /// Hook olayını gönderen sağlayıcının (`codex`, `antigravity`) CLI'ı.
    public init?(hookProvider: String) {
        guard let cli = Self.allCases.first(where: { $0.hookProvider == hookProvider }) else { return nil }
        self = cli
    }
}

/// Codex ve Antigravity oturumları proje klasöründe kendi TUI'leriyle çalışır; durumları hook'lardan gelir.
/// Codex hook'ları oturuma `-c` ile verilir (ilk kullanımda Codex'te `/hooks` ile bir kez onaylanır); Antigravity'nin
/// hook'ları kullanıcının `hooks.json` dosyasındaki kendi girdimizdedir (`AntigravityHooks`).
public enum AgentCLILaunch {
    /// Codex'e verilen hook olayları. Codex onayı tanımın özetine bağlar: komut her oturumda aynı kalmalı (oturum
    /// kimliği ortam değişkeniyle gelir), yoksa her oturumda yeniden onay ister.
    public static let codexHookEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                                         "PermissionRequest", "Stop", "Interrupt", "SessionEnd"]

    /// `-c hooks.<Olay>=[…]` değerleri (TOML). Zaman aşımı 3 sn: Codex SessionEnd ve Interrupt'ı zaten 3 sn'ye kırpar.
    public static func codexHookOverrides(hookCommand: String) -> [String] {
        codexHookEvents.map { event in
            #"hooks.\#(event)=[{matcher="*",hooks=[{type="command",command=\#(tomlString(hookCommand)),timeout=3}]}]"#
        }
    }

    /// Devam ettirme argümanları: bilinen oturum kimliği varsa o, yoksa klasördeki son oturum.
    public static func resumeArguments(for cli: AgentCLI, sessionID: String?) -> [String] {
        switch (cli, sessionID) {
        case (.codex, let id?): ["resume", id]
        case (.codex, nil): ["resume", "--last"]
        case (.antigravity, let id?): ["--conversation", id]
        case (.antigravity, nil): ["--continue"]
        case (.gemini, _): ["--resume", "latest"]
        }
    }

    /// `resume`: oturumdan devam eder. Devam edecek oturum yoksa CLI hemen hata verip çıkar; o zaman (ilk 5 saniyede
    /// sıfırdan farklı çıkış) yeni oturum açılır. Sonradan kapanan oturum yeniden başlatılmaz.
    /// `hookCommand`: verilirse oturum hook'ları açık başlar (Codex'te `-c`, Antigravity'de socket yeterli).
    public static func command(cli: AgentCLI, executablePath: String, resume: Bool, sessionID: String? = nil,
                               hookCommand: String? = nil, socketPath: String? = nil, cwd: String,
                               baseEnvironment: [String: String], tag: String) -> LaunchCommand {
        let executable = ClaudeLaunch.shellQuote(executablePath)
        var options: [String] = []
        if cli == .codex, let hookCommand {
            options = codexHookOverrides(hookCommand: hookCommand).flatMap { ["-c", $0] }
        }
        func invocation(_ args: [String]) -> String {
            ([executable] + (args + options).map(ClaudeLaunch.shellQuote)).joined(separator: " ")
        }
        let script: String
        if resume {
            script = """
            started=$SECONDS
            \(invocation(resumeArguments(for: cli, sessionID: sessionID)))
            code=$?
            if [ $code -ne 0 ] && [ $((SECONDS - started)) -lt 5 ]; then exec \(invocation([])); fi
            exit $code
            """
        } else {
            script = "exec \(invocation([]))"
        }
        let hooked = cli.hookProvider != nil && hookCommand != nil
        let environment = LaunchEnvironment.prepare(baseEnvironment, sessionID: tag, socketPath: hooked ? socketPath : nil)
        return LaunchCommand(executable: "/bin/zsh", args: ["-l", "-c", script], environment: environment, currentDirectory: cwd)
    }

    /// TOML temel dizgisi: ters bölü ve çift tırnak kaçırılır.
    static func tomlString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
