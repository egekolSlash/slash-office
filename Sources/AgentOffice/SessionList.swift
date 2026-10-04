import AgentOfficeCore
import AppKit
import SwiftUI

/// Sağ sütundaki kompakt oturum listesi. M3'te inspector bu alanı paylaşacak.
struct SessionList: View {
    @Bindable var model: AppModel
    let requestRemove: (String) -> Void

    var body: some View {
        List(model.store.sessions) { session in
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(.headline)
                StatusBadge(state: session.state, kind: model.kind(of: session.id))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.shift) { model.addTerminal(session.id) } else { model.showTerminal(session.id) }
            }
            .listRowBackground(model.layout.focused == session.id ? Color.accentColor.opacity(0.15) : Color.clear)
            .contextMenu {
                if session.state == .exited { Button("Devam ettir") { model.resume(session.id) } }
                Button("Kaldır", role: .destructive) { requestRemove(session.id) }
            }
        }
    }
}
