import AgentOfficeCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var pendingRemoval: (id: String, keepListFocus: Bool)?
    @State private var inspectorTab: InspectorTab =
        ProcessInfo.processInfo.environment["AGENT_OFFICE_DEMO_TAB"] == "diff" ? .changes : .sessions

    /// Çalışan bir ajanı kaldırmadan önce onay ister.
    private func requestRemove(_ id: String) { requestRemove(id, keepListFocus: false) }

    private func requestRemove(_ id: String, keepListFocus: Bool) {
        if model.isRunning(id) {
            pendingRemoval = (id, keepListFocus)
        } else {
            model.remove(id, keepListFocus: keepListFocus)
        }
    }

    var body: some View {
        Group {
            switch model.mode {
            case .office:
                office.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .work:
                HSplitView {
                    TerminalGrid(model: model, requestRemove: requestRemove)
                        .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
                    VSplitView {
                        office.frame(minHeight: 220, maxHeight: .infinity)
                        inspector.frame(minHeight: 160, maxHeight: .infinity)
                    }
                    .frame(minWidth: 240, idealWidth: 320, maxWidth: 480, maxHeight: .infinity)
                }
            case .focus:
                HStack(spacing: 0) {
                    TerminalGrid(model: model, requestRemove: requestRemove)
                    StatusStrip(model: model)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            Picker("Mod", selection: $model.mode) {
                Text("Ofis").tag(WorkspaceMode.office)
                Text("Çalışma").tag(WorkspaceMode.work)
                Text("Odak").tag(WorkspaceMode.focus)
            }
            .pickerStyle(.segmented)
            Menu("Yeni", systemImage: "plus") {
                Button("Claude oturumu") { model.chooseFolderAndStart(.claude) }
                Button("Terminal") { model.chooseFolderAndStart(.shell) }
            }
        }
        .confirmationDialog("Ajan hâlâ çalışıyor. Kaldırılırsa süreç kapatılır.",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Kapat ve kaldır", role: .destructive) {
                if let pendingRemoval { model.remove(pendingRemoval.id, keepListFocus: pendingRemoval.keepListFocus) }
                pendingRemoval = nil
            }
            .keyboardShortcut(.defaultAction)
        }
        .alert("Hata", isPresented: .constant(model.errorMessage != nil)) {
            Button("Tamam") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// Sağ sütunun alt kısmı: oturum listesi, odaktaki oturumun diff'i ve todo listesi.
    private var inspector: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $inspectorTab) {
                Text("Oturumlar").tag(InspectorTab.sessions)
                Text("Değişiklikler").tag(InspectorTab.changes)
                Text("Todo").tag(InspectorTab.todo)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(6)
            switch inspectorTab {
            case .sessions: SessionList(model: model, requestRemove: { requestRemove($0, keepListFocus: true) })
            case .changes: ChangesInspector(model: model)
            case .todo: TodoInspector(model: model)
            }
        }
    }

    private var office: some View {
        OfficeView(model: model)
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
