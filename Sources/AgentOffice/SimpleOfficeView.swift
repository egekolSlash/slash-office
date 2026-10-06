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
    @AppStorage("richOffice") private var richOffice = false

    var body: some View {
        Form {
            Toggle("Detaylı ofis", isOn: $richOffice)
            Text("Açıkken ofis gezinilebilir, odalı ve animasyonlu çizilir. Kapalıyken animasyonsuz, sade kartlar gösterilir (daha az CPU ve GPU).")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 420)
    }
}
