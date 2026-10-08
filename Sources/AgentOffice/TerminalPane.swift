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
            Text(TerminalLayout.isLauncher(id) ? String(localized: "New") : model.store.session(id)?.title ?? "?").font(.caption.bold())
            if let summary = model.workSummary(for: id) {
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
            if model.store.session(id)?.unseenFinish == true { FinishedBadge(compact: true) }
            if let state = model.store.session(id)?.state { StatusBadge(state: state, kind: model.kind(of: id)) }
            Spacer()
            Button { model.closePane(id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .help("Close pane (the session keeps running)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isFocused ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { model.showTerminal(id) }
        // Başlıktan tutup başka bir panelin kenarına (bölme) ya da ortasına (yer değiştirme) sürüklenir.
        .onDrag { model.beginPaneDrag(id, fromList: false) }
    }

    @ViewBuilder private var content: some View {
        if TerminalLayout.isLauncher(id) {
            LauncherPane(model: model, id: id)
        } else if model.backgroundSessions.contains(id), !model.isRunning(id) {
            BackgroundSessionView(model: model, id: id)
        } else if let session = model.store.session(id), session.state == .exited, model.terminals[id] == nil {
            StoppedSessionView(model: model, session: session, requestRemove: requestRemove)
        } else if let terminal = model.terminals[id] {
            VStack(spacing: 0) {
                TerminalHost(terminal: terminal).id(ObjectIdentifier(terminal))
                    .padding(.horizontal, model.appearance.paddingX)
                    .padding(.vertical, model.appearance.paddingY)
                    .background(Color(nsColor: model.appearance.background.nsColor))
            .overlay {
                // Süreç bitti: çıktı (hata mesajları dahil) arkada okunur kalır, eylemler ortada büyük kartta.
                if let session = model.store.session(id), session.state == .exited, model.hasEndedTerminal(id) {
                    StoppedSessionView(model: model, session: session, requestRemove: requestRemove, overTerminal: true)
                        .background(.black.opacity(0.25))
                }
            }
            }
        } else {
            ContentUnavailableView("Session not found", systemImage: "questionmark")
        }
    }
}

/// Uygulama dışında, Claude Code'un arka planında süren oturum: durumu listede ve ofiste görünür, burada açılabilir.
private struct BackgroundSessionView: View {
    @Bindable var model: AppModel
    let id: String

    var body: some View {
        ContentUnavailableView {
            Label("Running in the background", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
        } description: {
            Text("This Claude session is running in Claude Code's background; its status shows in the list and the office. Open it here to pick up where it left off; it keeps running even if the pane is closed.")
        } actions: {
            Button("Open Here") { model.resume(id) }
                .controlSize(.large)
        }
    }
}
