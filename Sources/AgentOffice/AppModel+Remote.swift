import AgentOfficeCore
import Foundation

extension AppModel {
    /// Telefondan mesaj gönderilebilir mi: oturum bu Mac'te bir panelde çalışıyor (arka plandaki ve durmuş oturumlar hayır).
    func canSendRemotely(_ id: String) -> Bool {
        terminals[id] != nil && isRunning(id) && store.session(id)?.state != .exited
    }

    func remoteTranscriptPath(_ id: String) -> String? { transcriptPaths[id] }

    /// Telefondan gelen komut. Başarıda nil, hatada telefonun çevireceği kod.
    func handleRemote(_ message: ClientMessage) -> String? {
        switch message {
        case .auth:
            return nil
        case .sendText(let id, let text):
            guard canSendRemotely(id), let terminal = terminals[id] else { return "not_running" }
            guard let paste = RemoteInput.paste(text, bracketedPaste: terminal.getTerminal().bracketedPasteMode) else {
                return "invalid_text"
            }
            DebugLog.write("remote text → \(id) (\(text.count) chars)")
            terminal.send(txt: paste)
            // Enter ayrı yazılır: yapıştırmayla aynı parçada gelirse yapıştırmanın içinde sayılabilir.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                terminal.send(txt: RemoteInput.submit)
            }
            return nil
        case .interrupt(let id):
            guard canSendRemotely(id), let terminal = terminals[id] else { return "not_running" }
            DebugLog.write("remote interrupt → \(id)")
            terminal.send(txt: RemoteInput.interrupt)
            return nil
        }
    }
}
