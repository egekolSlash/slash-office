/// Düz terminal oturumu: kullanıcının login shell'i, hook olmadan.
public enum ShellLaunch {
    public static func command(shellPath: String, cwd: String, sessionID: String,
                               baseEnvironment: [String: String]) -> LaunchCommand {
        LaunchCommand(executable: shellPath, args: ["-l"],
                      environment: LaunchEnvironment.prepare(baseEnvironment, sessionID: sessionID, socketPath: nil),
                      currentDirectory: cwd)
    }
}
