import AgentOfficeCore
import SwiftUI

/// Sade ofis (Ayarlar'da "Detaylı ofis" kapalıyken): animasyon ve 3D yok. Her depo bir oda kartı, her oturum
/// bir masa satırı; renkler durumu gösterir. Tıklama terminali açar, ⇧ ile yanına ekler.
struct SimpleOfficeView: View {
    @Bindable var model: AppModel

    var body: some View {
        let plan = model.officePlan()
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(plan.rooms, id: \.key) { room in
                    RoomCard(model: model, room: room)
                }
            }
            .padding(10)
        }
        .background(Color(nsColor: NSColor(red: 0.10, green: 0.10, blue: 0.15, alpha: 1)))
        .task(id: model.store.sessions.map(\.cwd)) { model.loadRoomKeys(model.store.sessions.map(\.cwd)) }
        .task(id: plan.rooms.map(\.key)) { model.loadProjectIcons(plan.rooms.map(\.key)) }
        .overlay {
            if plan.rooms.isEmpty {
                ContentUnavailableView("Ofis boş", systemImage: "building.2", description: Text("⌘T ile yeni panel aç."))
            }
        }
    }
}

private struct RoomCard: View {
    @Bindable var model: AppModel
    let room: OfficePlan.Room

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ProjectIconView(icon: model.projectIcons[room.key], size: 18)
                Text(room.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(ProjectPalette.color(for: room.key).opacity(0.9), in: RoundedRectangle(cornerRadius: 5))
            ForEach(room.desks, id: \.id) { desk in
                if let session = model.store.session(desk.id) {
                    DeskRow(model: model, session: session)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ProjectPalette.color(for: room.key).opacity(0.5)))
        .contextMenu { Button("Odayı düzenle…") { model.editingRoom = room.key } }
    }
}

private struct DeskRow: View {
    @Bindable var model: AppModel
    let session: AgentStore.Session

    var body: some View {
        let focused = model.layout.focused == session.id
        HStack(spacing: 6) {
            Circle().fill(Self.color(session.state)).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.worktree(for: session.cwd) ?? session.title)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                if let summary = session.workSummary {
                    Text(summary).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)).lineLimit(1).help(summary)
                }
            }
            Spacer(minLength: 4)
            if session.unseenFinish, session.state != .exited {
                FinishedBadge(compact: true)
            }
            if case .waiting = session.state {
                Text("?").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 16, height: 16).background(Circle().fill(.orange))
            } else {
                StatusBadge(state: session.state, kind: model.kind(of: session.id)).lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Self.color(session.state).opacity(focused ? 0.35 : 0.15), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(focused ? Color.white.opacity(0.7) : .clear))
        .contentShape(Rectangle())
        .contextMenu { Button("Görünümü düzenle…") { model.editingAvatar = session.id } }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.shift) { model.addTerminal(session.id) } else { model.showTerminal(session.id) }
        }
    }

    static func color(_ state: AgentState) -> Color {
        switch state {
        case .working: Color(red: 0.25, green: 0.52, blue: 0.95)
        case .waiting: Color(red: 0.98, green: 0.58, blue: 0.18)
        case .idle, .starting: Color(white: 0.62)
        case .exited: Color(white: 0.32)
        }
    }
}

/// Ayarlar (⌘,).
struct SettingsView: View {
    /// Yeniden başlatmadan önce uyarmak için çalışan ajan sayısı.
    var runningAgents: () -> Int = { 0 }
    @State private var language = AppRestart.language
    @State private var languageChanged = false
    @AppStorage("richOffice") private var richOffice = false
    @AppStorage(OfficeMetalView.dayNightKey) private var dayNight = true
    @AppStorage(OfficeView.autoFocusKey) private var autoFocus = true
    @AppStorage(OfficeMetalView.energySavingKey) private var energySaving = true

    var body: some View {
        Form {
            Picker("Language", selection: $language) {
                ForEach(AppLanguage.allCases, id: \.self) { option in
                    if option == .system { Text("System") } else { Text(verbatim: option.displayName) }
                }
            }
            .onChange(of: language) {
                AppRestart.apply(language)
                languageChanged = true
            }
            if languageChanged {
                HStack {
                    Text("The new language is used after a restart.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Restart Now") { AppRestart.relaunch(runningAgents: runningAgents()) }
                }
            }
            Divider()
            Toggle("Detaylı ofis", isOn: $richOffice)
            Text("Açıkken ofis gezinilebilir, odalı ve animasyonlu çizilir. Kapalıyken animasyonsuz, sade kartlar gösterilir (daha az CPU ve GPU).")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Gece/gündüz döngüsü", isOn: $dayNight).disabled(!richOffice)
            Text("Gökyüzü ve ışık bilgisayarın saatine göre değişir: gün doğumu, gündüz, gün batımı ve yıldızlı gece. Kapalıyken hep gündüz.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Mini ofiste otomatik odak", isOn: $autoFocus).disabled(!richOffice)
            Text("Çalışma modunda sağdaki ofis dikkat isteyen masaya kendiliğinden döner: soru soran, işi bitip görülmemiş, çalışan. Elle gezinince son hareketten 3 sn sonra devam eder; yeni bir soru beklemeden döndürür.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Energy saving", isOn: $energySaving).disabled(!richOffice)
            Text("On: villagers animate at 12–30 fps and the mini office at 12 fps. Off: the office always draws at your display's refresh rate (smoother, more CPU). Either way it stops while hidden.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 420)
    }
}
