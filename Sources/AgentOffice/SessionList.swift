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
                if NSEvent.modifierFlags.contains(.shift) {
                    model.addTerminal(id, takeKeyboard: false)
                } else {
                    model.showTerminal(id, takeKeyboard: false)
                }
            }
        )) {
            ForEach(model.store.sessions) { session in
                HStack(spacing: 8) {
                    ProjectIconView(icon: model.projectIcons[session.cwd], size: 28, isShell: model.kind(of: session.id) == .shell)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(verbatim: model.displayName(for: session.id)).font(.headline)
                            if model.look(for: session.id).name != nil {
                                Text(verbatim: session.title).font(.caption).foregroundStyle(.secondary)
                            }
                            if session.unseenFinish { FinishedBadge(tooltip: false) }
                        }
                        // İpucu (`.help`) yok: satır içindeki ipucu tıklamayı yutar, satır seçilemezdi.
                        if let summary = session.workSummary {
                            Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                        }
                        StatusBadge(state: session.state, kind: model.kind(of: session.id))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .tag(session.id)
                // Terminal alanındaki bir panelin kenarına sürükleyip bırakınca o yönden bölünür. `.onDrag` değil:
                // listede o, satırın yazısına ve ikonuna gelen tıklamaları yutar (satır seçilmez). `itemProvider`
                // tablonun kendi sürüklemesini kullanır; fare basılınca çağrılır, satır bırakınca seçilir, sürüklenince seçilmez.
                .itemProvider { model.beginPaneDrag(session.id) }
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
