import AgentOfficeCore
import SwiftUI

/// Kapanmış ya da uygulama yeniden açıldığında durmuş gelen oturum için terminal yerine gösterilir.
struct StoppedSessionView: View {
    let session: AgentStore.Session
    let onResume: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(session.title, systemImage: "pause.circle")
        } description: {
            VStack(spacing: 4) {
                Text("Bu oturum durdu. Kaldığı yerden devam ettirebilirsin.")
                Text(session.cwd).font(.caption).foregroundStyle(.secondary)
            }
        } actions: {
            HStack {
                Button("Devam ettir", action: onResume)
                    .keyboardShortcut(.defaultAction)
                Button("Kaldır", role: .destructive, action: onRemove)
            }
        }
    }
}
