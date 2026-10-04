import AgentOfficeCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var pendingRemoval: String?

    /// Çalışan bir ajanı kaldırmadan önce onay ister.
    private func requestRemove(_ id: String) {
        if model.isRunning(id) { pendingRemoval = id } else { model.remove(id) }
    }

    var body: some View {
        NavigationSplitView {
            List(model.store.sessions, selection: $model.selectedID) { session in
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title).font(.headline)
                    StatusBadge(state: session.state)
                    if let prompt = session.lastPrompt {
                        Text(prompt).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .tag(session.id)
                .contextMenu {
                    if session.state == .exited {
                        Button("Devam ettir") { model.resume(session.id) }
                    }
                    Button("Kaldır", role: .destructive) { requestRemove(session.id) }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar {
                Button("Yeni Claude oturumu", systemImage: "plus") { model.chooseFolderAndStart() }
                    .keyboardShortcut("n")
            }
        } detail: {
            if let id = model.selectedID, let session = model.store.session(id), session.state == .exited,
               model.terminals[id] == nil {
                StoppedSessionView(session: session,
                                   onResume: { model.resume(id) },
                                   onRemove: { model.remove(id) })
            } else if let id = model.selectedID, let terminal = model.terminals[id] {
                VStack(spacing: 0) {
                    if model.store.session(id)?.state == .exited, model.hasEndedTerminal(id) {
                        // Süreç bitti: terminal çıktısı (hata mesajları dahil) görünür kalır, üstte eylemler.
                        HStack {
                            Label("Oturum kapandı", systemImage: "pause.circle")
                            Spacer()
                            Button("Devam ettir") { model.resume(id) }.keyboardShortcut(.defaultAction)
                            Button("Kaldır", role: .destructive) { requestRemove(id) }
                        }
                        .padding(8)
                        .background(.bar)
                    }
                    TerminalHost(terminal: terminal).id(ObjectIdentifier(terminal))
                }
            } else {
                ContentUnavailableView("Oturum yok", systemImage: "terminal",
                                       description: Text("⌘N ile bir proje klasörü seçip Claude başlat."))
            }
        }
        .confirmationDialog("Ajan hâlâ çalışıyor. Kaldırılırsa süreç kapatılır.",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Kapat ve kaldır", role: .destructive) {
                if let id = pendingRemoval { model.remove(id) }
                pendingRemoval = nil
            }
        }
        .alert("Hata", isPresented: .constant(model.errorMessage != nil)) {
            Button("Tamam") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
