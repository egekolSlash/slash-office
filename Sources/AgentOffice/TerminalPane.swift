import AgentOfficeCore
import SwiftUI

struct TerminalPane: View {
    @Bindable var model: AppModel
    let id: String
    let requestRemove: (String) -> Void

    private var isFocused: Bool { model.layout.focused == id }

    var body: some View {
        VStack(spacing: 0) {
            header
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(isFocused ? Color.accentColor : .clear, lineWidth: 2))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.store.session(id)?.title ?? "?").font(.caption.bold())
            if let state = model.store.session(id)?.state { StatusBadge(state: state, kind: model.kind(of: id)) }
            Spacer()
            Button { model.closePane(id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .help("Paneli kapat (oturum çalışmaya devam eder)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isFocused ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { model.showTerminal(id) }
    }

    @ViewBuilder private var content: some View {
        if let session = model.store.session(id), session.state == .exited, model.terminals[id] == nil {
            StoppedSessionView(session: session, onResume: { model.resume(id) }, onRemove: { model.remove(id) })
        } else if let terminal = model.terminals[id] {
            VStack(spacing: 0) {
                if model.store.session(id)?.state == .exited, model.hasEndedTerminal(id) {
                    // Süreç bitti: terminal çıktısı (hata mesajları dahil) görünür kalır, üstte eylemler.
                    HStack {
                        Label("Oturum kapandı", systemImage: "pause.circle")
                        Spacer()
                        Button("Devam ettir") { model.resume(id) }
                        Button("Kaldır", role: .destructive) { requestRemove(id) }
                    }
                    .padding(8)
                    .background(.bar)
                }
                TerminalHost(terminal: terminal).id(ObjectIdentifier(terminal))
            }
        } else {
            ContentUnavailableView("Oturum bulunamadı", systemImage: "questionmark")
        }
    }
}
