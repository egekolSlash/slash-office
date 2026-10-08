import AgentOfficeCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @AppStorage("richOffice") private var richOffice = false
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

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            switch model.mode {
            case .office:
                office(interactive: true).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .work:
                HSplitView {
                    TerminalGrid(model: model, requestRemove: requestRemove)
                        .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
                    VSplitView {
                        office(interactive: false).frame(minHeight: 220, maxHeight: .infinity)
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
            Picker("Mode", selection: $model.mode) {
                Text("Office").tag(WorkspaceMode.office)
                Text("Work").tag(WorkspaceMode.work)
                Text("Focus").tag(WorkspaceMode.focus)
            }
            .pickerStyle(.segmented)
            Menu("New", systemImage: "plus") {
                Button("Claude Session") { model.openLauncher(beside: false, claude: true) }
                Button("Terminal") { model.newShellSession(cwd: URL(fileURLWithPath: NSHomeDirectory())) }
                Button("Terminal in Folder…") { model.chooseFolderAndStart(.shell) }
            }
        }
        .confirmationDialog("The agent is still running. Removing it will end its process.",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Stop and Remove", role: .destructive) {
                if let pendingRemoval { model.remove(pendingRemoval.id, keepListFocus: pendingRemoval.keepListFocus) }
                pendingRemoval = nil
            }
            .keyboardShortcut(.defaultAction)
        }
        .sheet(isPresented: $model.showPermissions) {
            PermissionsView { model.finishPermissions() }
        }
        // "Edit Appearance…" (sağ tık, liste): özelleştirme penceresi o köylü seçili açılır.
        .onChange(of: model.editingAvatar) {
            guard let id = model.editingAvatar else { return }
            model.customizingAgent = id
            model.editingAvatar = nil
            openWindow(id: "agents")
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView(model: model)
        }
        .sheet(isPresented: Binding(get: { model.editingRoom != nil }, set: { if !$0 { model.editingRoom = nil } })) {
            if let key = model.editingRoom { RoomEditorSheet(model: model, roomKey: key) }
        }
        .alert("Error", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// Sağ sütunun alt kısmı: oturum listesi, odaktaki oturumun diff'i ve todo listesi.
    private var inspector: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $inspectorTab) {
                Text("Sessions").tag(InspectorTab.sessions)
                Text("Changes").tag(InspectorTab.changes)
                Text("To-Do").tag(InspectorTab.todo)
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

    /// Ayarlar'daki "Detaylı ofis": açıkken SpriteKit ofisi, kapalıyken sade kartlar.
    @ViewBuilder private func office(interactive: Bool) -> some View {
        if richOffice {
            OfficeView(model: model, interactive: interactive)
        } else {
            SimpleOfficeView(model: model)
        }
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
                    .help(model.displayName(for: session.id))
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
