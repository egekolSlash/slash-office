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
        Group {
            switch model.mode {
            case .office:
                office
            case .work:
                HSplitView {
                    TerminalGrid(model: model, requestRemove: requestRemove).frame(minWidth: 500)
                    VSplitView {
                        office.frame(minHeight: 220)
                        SessionList(model: model, requestRemove: requestRemove).frame(minHeight: 120)
                    }
                    .frame(minWidth: 240, idealWidth: 320, maxWidth: 480)
                }
            case .focus:
                HStack(spacing: 0) {
                    TerminalGrid(model: model, requestRemove: requestRemove)
                    StatusStrip(model: model)
                }
            }
        }
        .toolbar {
            Picker("Mod", selection: $model.mode) {
                Text("Ofis").tag(WorkspaceMode.office)
                Text("Çalışma").tag(WorkspaceMode.work)
                Text("Odak").tag(WorkspaceMode.focus)
            }
            .pickerStyle(.segmented)
            Button("Yeni Claude oturumu", systemImage: "plus") { model.chooseFolderAndStart() }
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

    private var office: some View {
        // Task 6'da OfficeView ile değiştirilecek.
        ContentUnavailableView("Ofis", systemImage: "building.2")
    }
}

/// Odak modunda sağ kenardaki ince durum şeridi: her oturum için bir nokta, tıklayınca o terminal.
struct StatusStrip: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.store.sessions) { session in
                Circle()
                    .fill(color(session.state))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(model.layout.focused == session.id ? Color.primary : .clear, lineWidth: 2))
                    .help(session.title)
                    .onTapGesture { model.showTerminal(session.id) }
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .frame(width: 24)
        .background(.bar)
    }

    private func color(_ state: AgentState) -> Color {
        switch state {
        case .waiting: .orange
        case .working: .blue
        case .exited: .gray.opacity(0.4)
        default: .gray
        }
    }
}
