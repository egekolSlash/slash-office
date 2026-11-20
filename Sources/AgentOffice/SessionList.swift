import AgentOfficeCore
import AppKit
import SwiftUI

/// Sağ sütundaki oturum listesi. Native seçim: satırın her yeri tıklanır; ⇧ ile terminal yanına eklenir.
/// Fareyle tıklanınca terminal gösterilir ve klavyeyi alır (doğrudan yazılabilir). ↑/↓ ile gezinirken klavye listede
/// kalır, ↩ terminale geçer; ⌫ / ⌘⌫ oturumu listeden kaldırır. Satır bir panelin kenarına sürüklenirse panel o yönden bölünür; listenin içinde
/// sürüklenirse yeri değişir (sıralama "Elle"ye geçer). Sağ üstteki menü listeyi aktifliğe, projeye, ada... göre dizer.
struct SessionList: View {
    @Bindable var model: AppModel
    let requestRemove: (String) -> Void
    /// Aktiflik ve son olay sıralamaları zamanla değişir; yarım dakikada bir yeniden dizilir.
    @State private var now = Date.now
    @State private var clickMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            header
            list
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
        .onAppear {
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [model] event in
                MainActor.assumeIsolated { SelectedRowClick.watch(event, model: model) }
                return event
            }
        }
        .onDisappear {
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            clickMonitor = nil
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            let stopped = model.stoppedSessionIDs.count
            if stopped >= 2 {
                Button { model.resumeAllStopped() } label: {
                    Label("Resume All (\(stopped))", systemImage: "play.square.stack")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .help("Resume all stopped sessions where they left off (⌘⇧R)")
            } else {
                Spacer(minLength: 0)
            }
            sortMenu
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $model.sessionSort) {
                ForEach(SessionSort.allCases) { sort in
                    Label(sort.title, systemImage: sort.symbol).tag(sort)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label {
                Text(model.sessionSort.title)
            } icon: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .fixedSize()
        .foregroundStyle(model.sessionSort == .manual ? .secondary : .primary)
        .help("Sort sessions. Drag a session in the list to put it in your own order.")
    }

    /// Seçim fareyle mi değişti (klavyeyle gezinmede klavye listede kalır).
    private static func isMouseClick(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        return [.leftMouseDown, .leftMouseUp, .leftMouseDragged].contains(event.type)
    }

    private var list: some View {
        let shown = model.listedSessionIDs(now: now)
        return List(selection: Binding(
            get: { model.layout.focused },
            set: { id in
                guard let id else { return }
                let byMouse = Self.isMouseClick(NSApp.currentEvent)
                DebugLog.write("list select \(id) byMouse=\(byMouse)")
                if NSEvent.modifierFlags.contains(.shift) {
                    model.addTerminal(id, takeKeyboard: byMouse)
                } else {
                    model.showTerminal(id, takeKeyboard: byMouse)
                }
            }
        )) {
            ForEach(shown.compactMap(model.store.session)) { session in
                HStack(spacing: 8) {
                    ProjectIconView(icon: model.projectIcons[session.cwd], size: 28, isShell: model.kind(of: session.id) == .shell)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(verbatim: model.displayName(for: session.id)).font(.headline)
                            if session.unseenFinish { FinishedBadge(tooltip: false) }
                        }
                        // İpucu (`.help`) yok: satır içindeki ipucu tıklamayı yutar, satır seçilemezdi.
                        if let summary = session.workSummary {
                            Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                        }
                        StatusBadge(state: session.state, kind: model.kind(of: session.id), background: session.backgroundTasks)
                    }
                    Spacer(minLength: 0)
                    if model.kind(of: session.id).isAgent || !session.touchedFiles.isEmpty {
                        SessionFilesButton(model: model, sessionID: session.id)
                    }
                    // Oturumlar birbirine göre sıralandığı için hepsinin kaydı verilir; yarım dakikada bir yenilenir.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        let logs = Dictionary(model.store.sessions.map { ($0.id, $0.activity) }) { first, _ in first }
                        ActivityStripe(level: ActivityHeat.levels(logs, now: context.date)[session.id] ?? 0)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .contentShape(Rectangle())
                .tag(session.id)
                // Terminal alanındaki bir panelin kenarına sürükleyip bırakınca o yönden bölünür. `.onDrag` değil:
                // listede o, satırın yazısına ve ikonuna gelen tıklamaları yutar (satır seçilmez). `itemProvider`
                // tablonun kendi sürüklemesini kullanır; fare basılınca çağrılır, satır bırakınca seçilir, sürüklenince seçilmez.
                .itemProvider { model.beginPaneDrag(session.id) }
            }
            .onMove { offsets, destination in
                withAnimation { model.moveSessions(from: offsets, to: destination, shown: shown) }
            }
        }
        .animation(.default, value: shown)
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first {
                if model.store.session(id)?.state == .exited { Button("Resume") { model.resume(id) } }
                Button("Edit Appearance…") { model.editingAvatar = id }
                Button("Remove", role: .destructive) { requestRemove(id) }
            }
        } primaryAction: { ids in
            if let id = ids.first { model.showTerminal(id) }
        }
        .task(id: model.store.sessions.map(\.cwd)) {
            model.loadProjectIcons(model.store.sessions.map(\.cwd))
            // Proje sıralamasında worktree'ler ana depoyla aynı grupta olsun.
            model.loadRoomKeys(model.store.sessions.map(\.cwd))
        }
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

/// Zaten seçili satıra tıklanınca liste seçimi değişmez, seçim bağlaması çağrılmaz; terminale yine de geçilsin.
/// Satıra bir hareket (`TapGesture`) eklemek tablonun seçimini ve sürüklemesini bozuyor, bu yüzden fare olayı izlenir:
/// seçili satıra basılıp aynı satırda bırakılırsa (sürüklenmediyse) odaktaki terminal klavyeyi alır.
@MainActor
private enum SelectedRowClick {
    static func watch(_ event: NSEvent, model: AppModel) {
        guard event.clickCount == 1, !event.modifierFlags.contains(.shift), let window = event.window,
              let hit = window.contentView?.hitTest(event.locationInWindow) else { return }
        var view: NSView? = hit
        while let current = view, !(current is NSTableView) { view = current.superview }
        guard let table = view as? NSTableView else { return }
        let row = table.row(at: table.convert(event.locationInWindow, from: nil))
        let ids = model.listedSessionIDs()
        // Bu tablo oturum listesi mi (satır sayısı ve seçili satır odaktaki oturum).
        guard row >= 0, row == table.selectedRow, table.numberOfRows == ids.count,
              let id = model.layout.focused, ids[row] == id else { return }
        waitForRelease(table: table, row: row, id: id, model: model, tries: 0)
    }

    private static func waitForRelease(table: NSTableView, row: Int, id: String, model: AppModel, tries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            MainActor.assumeIsolated {
                if NSEvent.pressedMouseButtons & 1 != 0 {
                    if tries < 200 { waitForRelease(table: table, row: row, id: id, model: model, tries: tries + 1) }
                    return
                }
                guard let window = table.window, model.layout.focused == id else { return }
                let point = table.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                guard table.row(at: point) == row else { return }
                DebugLog.write("list click on selected \(id)")
                model.focusTerminalView()
            }
        }
    }
}
