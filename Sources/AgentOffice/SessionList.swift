import AgentOfficeCore
import AppKit
import SwiftUI

/// Sağ sütundaki oturum listesi. Native seçim: satırın her yeri tıklanır; ⇧ ile terminal yanına eklenir.
struct SessionList: View {
    @Bindable var model: AppModel
    let requestRemove: (String) -> Void

    var body: some View {
        List(selection: Binding(
            get: { model.layout.focused },
            set: { id in
                guard let id else { return }
                if NSEvent.modifierFlags.contains(.shift) { model.addTerminal(id) } else { model.showTerminal(id) }
            }
        )) {
            ForEach(model.store.sessions) { session in
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title).font(.headline)
                    StatusBadge(state: session.state, kind: model.kind(of: session.id))
                }
                .tag(session.id)
                .contextMenu {
                    if session.state == .exited { Button("Devam ettir") { model.resume(session.id) } }
                    Button("Kaldır", role: .destructive) { requestRemove(session.id) }
                }
            }
        }
    }
}
