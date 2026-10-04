import AgentOfficeCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

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
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar {
                Button("Yeni Claude oturumu", systemImage: "plus") { model.chooseFolderAndStart() }
                    .keyboardShortcut("n")
            }
        } detail: {
            if let id = model.selectedID, let terminal = model.terminals[id] {
                TerminalHost(terminal: terminal).id(id)
            } else {
                ContentUnavailableView("Oturum yok", systemImage: "terminal",
                                       description: Text("⌘N ile bir proje klasörü seçip Claude başlat."))
            }
        }
        .alert("Hata", isPresented: .constant(model.errorMessage != nil)) {
            Button("Tamam") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
