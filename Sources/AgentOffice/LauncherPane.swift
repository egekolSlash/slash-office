import AgentOfficeCore
import SwiftUI

/// ⌘T / ⌘D ile açılan boş panel: T terminal (ana klasörde), C Claude (proje bu panelin içinde seçilir), F terminal
/// için klasör. Proje seçicide ⌘O başka bir klasör, ⇧⌘O proje klasörü ekler (altındaki her klasör listelenir).
struct LauncherPane: View {
    @Bindable var model: AppModel
    let id: String
    @State private var step: Step
    @State private var query = ""
    @State private var selection: String?
    @FocusState private var focus: Field?

    enum Step { case choose, project(SessionKind) }

    init(model: AppModel, id: String) {
        self.model = model
        self.id = id
        // ⌘N doğrudan Claude proje seçimiyle açılır.
        _step = State(initialValue: AppModel.launcherStartsWithClaude(id) ? .project(.claude) : .choose)
        _selection = State(initialValue: model.pickerProjects.first)
    }
    enum Field { case choice, search }

    var body: some View {
        Group {
            switch step {
            case .choose: choose
            case .project(let kind): projectPicker(kind)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: model.appearance.background.nsColor))
        .environment(\.colorScheme, .dark)
        .onAppear { if case .choose = step { focus = .choice } else { focus = .search } }
        // Panel tıklanınca odak buraya gelsin (terminal yerine).
        .contentShape(Rectangle())
        .onTapGesture {
            model.layout.show(id)
            model.releaseTerminalKeyboard()
            if case .choose = step { focus = .choice } else { focus = .search }
        }
    }

    // MARK: - Seçim

    private var choose: some View {
        VStack(spacing: 18) {
            Text("What would you like to open?").font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
            HStack(spacing: 14) {
                ChoiceButton(key: "T", title: "Terminal", detail: "In your home folder", symbol: "apple.terminal") { openTerminal() }
                ChoiceButton(key: "C", title: "Claude", detail: "Choose a project", symbol: "sparkles") { startPicking(.claude) }
            }
            Button { startPicking(.shell) } label: {
                HStack(spacing: 6) {
                    Text("Choose Folder for Terminal…")
                    KeyCap("F")
                }
            }
            .buttonStyle(.link)
            .font(.callout)
            Text("Press Esc to close").font(.caption).foregroundStyle(.white.opacity(0.4))
        }
        .padding(24)
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .choice)
        .onKeyPress(characters: .letters) { press in
            switch press.characters.lowercased() {
            case "t": openTerminal(); return .handled
            case "c": startPicking(.claude); return .handled
            case "f": startPicking(.shell); return .handled
            default: return .ignored
            }
        }
        .onKeyPress(.escape) { model.closePane(id); return .handled }
    }

    private func openTerminal() {
        model.newShellSession(cwd: URL(fileURLWithPath: NSHomeDirectory()), replacing: id)
    }

    private func startPicking(_ kind: SessionKind) {
        query = ""
        model.watchProjectRoots()
        selection = model.pickerProjects.first
        step = .project(kind)
        focus = .search
    }

    // MARK: - Proje seçimi

    private func projectPicker(_ kind: SessionKind) -> some View {
        let projects = RecentProjects.filter(model.pickerProjects, query: query)
        // Kısayollar yalnız odaktaki panelde: iki seçici açıkken ⌘O ikisini birden tetiklemesin.
        let active = model.layout.focused == id
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kind == .claude ? String(localized: "Claude: choose a project") : String(localized: "Terminal: choose a folder")).font(.headline)
                Spacer()
                Text("↑↓ select · ↩ open · ⌘O other folder · Esc back").font(.caption).foregroundStyle(.secondary)
            }
            TextField("Search…", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .search)
                .onChange(of: query) { selection = RecentProjects.filter(model.pickerProjects, query: query).first }
                .onKeyPress(.downArrow) { move(1, in: projects); return .handled }
                .onKeyPress(.upArrow) { move(-1, in: projects); return .handled }
                .onKeyPress(.escape) { step = .choose; focus = .choice; return .handled }
                .onSubmit { if let selection { open(selection, kind) } }
            ScrollViewReader { proxy in
                List(selection: $selection) {
                    ForEach(projects, id: \.self) { path in
                        ProjectRow(path: path, icon: model.projectIcons[path]).tag(path).id(path)
                    }
                }
                .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { paths in
                    if let path = paths.first { open(path, kind) }
                }
                .onChange(of: selection) { if let selection { proxy.scrollTo(selection) } }
                .overlay {
                    if projects.isEmpty {
                        ContentUnavailableView(model.pickerProjects.isEmpty ? String(localized: "No projects yet") : String(localized: "No matching projects"),
                                               systemImage: "folder", description: Text("Choose one with Other Folder… (⌘O), or add the folder that holds your projects (⇧⌘O)."))
                    }
                }
            }
            if !model.projectRoots.isEmpty { projectRootsRow }
            HStack {
                Button("Other Folder…") { model.chooseFolderAndStart(kind, replacing: id) }
                    .keyboardShortcut(active ? KeyboardShortcut("o", modifiers: .command) : nil)
                    .help("Open any folder (⌘O)")
                Button("Add Projects Folder…") { model.addProjectRoot(); focus = .search }
                    .keyboardShortcut(active ? KeyboardShortcut("o", modifiers: [.command, .shift]) : nil)
                    .help("Add a folder that holds your projects: every folder inside it is listed here and kept up to date (⇧⌘O)")
                Spacer()
                Button("Open") { if let selection { open(selection, kind) } }
                    .disabled(selection == nil)
            }
        }
        .padding(16)
        .frame(maxWidth: 560)
        .task(id: projects) { model.loadProjectIcons(projects) }
    }

    /// Proje klasörleri; her birinin yanında listeden çıkarma düğmesi.
    private var projectRootsRow: some View {
        HStack(spacing: 8) {
            Text("Projects from:").foregroundStyle(.secondary)
            ForEach(model.projectRoots, id: \.self) { root in
                HStack(spacing: 3) {
                    Text(verbatim: (root as NSString).abbreviatingWithTildeInPath)
                    Button { model.removeProjectRoot(root) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Stop listing the projects in this folder")
                }
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .lineLimit(1)
    }

    private func move(_ step: Int, in projects: [String]) {
        guard !projects.isEmpty else { return }
        let index = selection.flatMap { projects.firstIndex(of: $0) } ?? -1
        selection = projects[min(max(index + step, 0), projects.count - 1)]
    }

    private func open(_ path: String, _ kind: SessionKind) {
        guard FileManager.default.fileExists(atPath: path) else {
            model.errorMessage = String(localized: "Folder not found: \(path)")
            return
        }
        let url = URL(fileURLWithPath: path)
        switch kind {
        case .claude: model.newClaudeSession(cwd: url, replacing: id)
        case .shell: model.newShellSession(cwd: url, replacing: id)
        }
    }
}

private struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(verbatim: key)
            .font(.system(.caption, design: .monospaced).bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct ChoiceButton: View {
    let key: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 28))
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                Text(key)
                    .font(.system(.callout, design: .monospaced).bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
            .frame(width: 150, height: 150)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

private struct ProjectRow: View {
    let path: String
    let icon: LoadedProjectIcon?

    var body: some View {
        HStack(spacing: 10) {
            ProjectIconView(icon: icon, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text((path as NSString).lastPathComponent).font(.body.weight(.medium))
                Text((path as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
