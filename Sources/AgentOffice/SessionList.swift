import AgentOfficeCore
import AppKit
import SwiftUI

/// Sağ sütundaki oturum listesi. Native seçim: satırın her yeri tıklanır; ⇧ ile terminal yanına eklenir.
/// Seçim terminali gösterir ama klavye listede kalır: ↑/↓ ile gezinilir, ↩ ya da çift tık terminale geçer,
/// ⌫ / ⌘⌫ oturumu listeden kaldırır. Satır bir panelin kenarına sürüklenirse panel o yönden bölünür.
struct SessionList: View {
    @Bindable var model: AppModel
    let requestRemove: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            let stopped = model.stoppedSessionIDs.count
            if stopped >= 2 {
                Button { model.resumeAllStopped() } label: {
                    Label("Resume All (\(stopped))", systemImage: "play.square.stack")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .help("Resume all stopped sessions where they left off (⌘⇧R)")
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            list
        }
    }

    private var list: some View {
        List(selection: Binding(
            get: { model.layout.focused },
            set: { id in
                guard let id else { return }
                let before = model.layout
                if NSEvent.modifierFlags.contains(.shift) {
                    model.addTerminal(id, takeKeyboard: false)
                } else {
                    model.showTerminal(id, takeKeyboard: false)
                }
                model.noteListSelection(id, before: before)
            }
        )) {
            ForEach(model.store.sessions) { session in
                HStack(spacing: 8) {
                    ProjectIconView(icon: model.projectIcons[session.cwd], size: 28, isShell: model.kind(of: session.id) == .shell)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(session.title).font(.headline)
                            if session.unseenFinish { FinishedBadge() }
                        }
                        if let summary = session.workSummary {
                            Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                                .help(summary)
                        }
                        StatusBadge(state: session.state, kind: model.kind(of: session.id))
                    }
                }
                .tag(session.id)
                // Terminal alanındaki bir panelin kenarına sürükleyip bırakınca o yönden bölünür.
                .onDrag { model.beginPaneDrag(session.id, fromList: true) }
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first {
                if model.store.session(id)?.state == .exited { Button("Resume") { model.resume(id) } }
                Button("Edit Appearance…") { model.editingAvatar = id }
                Button("Remove", role: .destructive) { requestRemove(id) }
            }
        } primaryAction: { ids in
            if let id = ids.first { model.showTerminal(id) }
        }
        .task(id: model.store.sessions.map(\.cwd)) { model.loadProjectIcons(model.store.sessions.map(\.cwd)) }
        .onKeyPress(.return) {
            guard let id = model.layout.focused else { return .ignored }
            model.showTerminal(id)
            return .handled
        }
        .onKeyPress(.delete) {
            guard let id = model.layout.focused else { return .ignored }
            requestRemove(id)
            return .handled
        }
    }
}
