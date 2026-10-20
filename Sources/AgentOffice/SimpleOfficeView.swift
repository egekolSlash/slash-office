import AgentOfficeCore
import SwiftUI
import UniformTypeIdentifiers

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
                ContentUnavailableView("The office is empty", systemImage: "building.2", description: Text("Press ⌘T to open a new pane."))
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
        .contextMenu { Button("Edit Room…") { model.editingRoom = room.key } }
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
                Text(verbatim: model.worktree(for: session.cwd) ?? session.title)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                if let summary = session.workSummary {
                    Text(summary).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if session.unseenFinish, session.state != .exited {
                FinishedBadge(compact: true)
            }
            if case .waiting = session.state {
                Text(verbatim: "?").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
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
        .contextMenu { Button("Edit Appearance…") { model.editingAvatar = session.id } }
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
    /// Telefondan erişim bölümü; önizlemelerde nil.
    var remote: RemoteBridge?
    @State private var language = AppRestart.language
    @AppStorage("richOffice") private var richOffice = false
    @AppStorage(OfficeMetalView.dayNightKey) private var dayNight = true
    @AppStorage(OfficeView.autoFocusKey) private var autoFocus = true
    @AppStorage(OfficeMetalView.energySavingKey) private var energySaving = true
    @AppStorage(AppModel.deskOrientationKey) private var deskOrientation = DeskOrientation.horizontal
    @AppStorage(NotificationPrefs.finishedKey) private var notifyFinished = true
    @AppStorage(NotificationPrefs.dockBounceKey) private var dockBounce = true
    @AppStorage(NotificationPrefs.soundKey) private var playSound = true
    @AppStorage(NotificationPrefs.soundFileKey) private var soundFile = ""
    @AppStorage(Notifier.soundNameKey) private var soundName = ""
    @State private var soundError = false

    var body: some View {
        Form {
            Picker("Language", selection: $language) {
                ForEach(AppLanguage.allCases, id: \.self) { option in
                    if option == .system { Text("System") } else { Text(verbatim: option.displayName) }
                }
            }
            .onChange(of: language) { AppRestart.apply(language) }
            if language.needsRestart(launched: AppRestart.launchedLanguage) {
                HStack {
                    Text("The new language is used after a restart.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Restart Now") { AppRestart.relaunch(runningAgents: runningAgents()) }
                }
            }
            Divider()
            Toggle("Office view", isOn: $richOffice)
            Text("When on, the office is drawn with rooms and animation, and you can navigate it. When off, it shows plain cards without animation (less CPU and GPU).")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("Desks", selection: $deskOrientation) {
                Text("Horizontal").tag(DeskOrientation.horizontal)
                Text("Vertical").tag(DeskOrientation.vertical)
            }
            .pickerStyle(.segmented)
            .disabled(!richOffice)
            Text("Horizontal: agents sit behind their desks facing you. Vertical: desks run along the room and agents face the corridor.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Day and night", isOn: $dayNight).disabled(!richOffice)
            Text("The sky and light follow your computer's clock: sunrise, day, sunset and a starry night. When off, it is always daytime.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Mini office auto-focus", isOn: $autoFocus).disabled(!richOffice)
            Text("In Work mode, the office on the right turns to the desk that needs attention by itself: asking a question, working, or finished but unseen. After you move it by hand it resumes 3 seconds after your last move; a new question turns it right away.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Energy saving", isOn: $energySaving)
            Text("On: villagers animate at 12–30 fps, the mini office at 12 fps, and terminals without the keyboard redraw a few times a second (a terminal you scroll stays smooth). Off: the office draws at your display's refresh rate and every terminal in the window redraws right away (smoother, more CPU). Either way the office stops while hidden.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Toggle("Notify when an agent finishes", isOn: $notifyFinished)
            Text("While you're in another app, a notification appears in the corner of the screen when an agent finishes its task. Questions and permission requests are always notified.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Bounce the Dock icon", isOn: $dockBounce)
            Text("The icon bounces once when an agent finishes, and keeps bouncing until you come back when one is waiting for you.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Play a sound", isOn: $playSound)
            HStack {
                if soundFile.isEmpty {
                    Text("System sound")
                } else {
                    Text("Sound: \(soundName.isEmpty ? (soundFile as NSString).lastPathComponent : soundName)")
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button {
                    Notifier.playPreview()
                } label: {
                    Image(systemName: "play.fill")
                }
                .help("Play")
                Button("Choose…") { chooseSound() }
                if !soundFile.isEmpty {
                    Button("Reset to Default") { Notifier.resetSound() }
                }
            }
            .disabled(!playSound)
            Text("Choose your own MP3, M4A, WAV or AIFF file. Slash Office keeps a copy, so moving or deleting the original is fine.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if soundError {
                Text("This file couldn't be used as a sound.").font(.callout).foregroundStyle(.red)
            }
            if let remote {
                Divider()
                RemoteSettingsSection(remote: remote)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func chooseSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = NotificationPolicy.soundExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Notifier.importSound(from: url)
            soundError = false
            Notifier.playPreview()
        } catch {
            soundError = true
        }
    }
}
