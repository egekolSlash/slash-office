import Foundation

/// `agent-office-hook <provider>`: stdin'deki hook JSON'unu uygulamaya iletir.
/// Ajanı asla etkilememeli: her zaman 0 döner, stdout'a yazmaz.
public enum HookCLI {
    public static func run(arguments: [String], environment: [String: String], stdin: Data) -> Int32 {
        guard let session = environment["AGENT_OFFICE_SESSION"],
              let socketPath = environment["AGENT_OFFICE_SOCKET"] else { return 0 }
        let provider = arguments.dropFirst().first ?? "claude"
        if let line = HookEnvelope.encodeLine(session: session, provider: provider, rawPayload: stdin) {
            HookClient.send(line, toSocket: socketPath)
        }
        return 0
    }
}
