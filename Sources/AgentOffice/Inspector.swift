import AgentOfficeCore
import AppKit
import SwiftUI

enum InspectorTab: Hashable {
    case sessions, changes, todo
}

/// Cursor/VS Code'daki "Changes" görünümü gibi: gruplu dosya listesi, altında seçili dosyanın diff'i.
struct ChangesInspector: View {
    @Bindable var model: AppModel
    @State private var selection: String?

    var body: some View {
        if let id = model.layout.focused, let session = model.store.session(id) {
            let state = model.diffWatcher.state(id, model.changesScope)
            VStack(spacing: 0) {
                header(session: session, state: state)
                Picker("Scope", selection: $model.changesScope) {
                    Text("Uncommitted").tag(ChangesScope.uncommitted)
                    Text("Last Turn").tag(ChangesScope.lastTurn)
                    Text("Session").tag(ChangesScope.session)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                Divider()
                content(session: session, state: state)
            }
            .onAppear { model.requestDiff(id, immediately: true) }
            .onChange(of: id) { _, newID in model.requestDiff(newID, immediately: true) }
            .onChange(of: model.changesScope) { _, _ in model.requestDiff(id, immediately: true) }
        } else {
            ContentUnavailableView("No session selected", systemImage: "doc.text.magnifyingglass")
        }
    }

    private func header(session: AgentStore.Session, state: DiffState?) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: model.displayName(for: session.id)).font(.headline)
            if case .ready(_, let branch?) = state {
                Label(branch, systemImage: "arrow.triangle.branch").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if case .ready(let groups, _) = state {
                Text("Files: \(groups.reduce(0) { $0 + $1.files.count })").font(.caption).foregroundStyle(.secondary)
            }
            Button { model.requestDiff(session.id, immediately: true) } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain)
                .help("Refresh")
        }
        .padding(8)
    }

    @ViewBuilder
    private func content(session: AgentStore.Session, state: DiffState?) -> some View {
        switch state {
        case nil, .loading?:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable(let reason)?:
            ContentUnavailableView("No changes to show", systemImage: "clock", description: Text(reason))
        case .noRepository?:
            if session.touchedFiles.isEmpty {
                ContentUnavailableView("Not a Git repository", systemImage: "folder",
                                       description: Text("Files the agent touches will be listed here."))
            } else {
                let urls = Dictionary(session.touchedFiles.map { ($0, Self.url(of: $0, in: session.cwd)) }) { first, _ in first }
                List(session.touchedFiles, id: \.self, selection: $selection) { path in
                    FileRow(path: path, detail: nil)
                }
                .fileActions(selection: $selection) { urls[$0] }
            }
        case .ready(let groups, _)?:
            if groups.isEmpty {
                ContentUnavailableView("No changes", systemImage: "checkmark.circle",
                                       description: Text(model.changesScope == .uncommitted ? String(localized: "Everything is committed.") : ""))
            } else {
                let selected = selectedFile(in: groups)
                let urls = Dictionary(groups.flatMap { group in group.files.map { (Self.tag(group, $0), group.url(of: $0)) } }) { first, _ in first }
                VSplitView {
                    List(selection: $selection) {
                        ForEach(groups) { group in
                            Section(String("\(group.title) · \(group.files.count)")) {
                                ForEach(group.files) { file in
                                    FileRow(path: file.path, detail: file).tag(Self.tag(group, file))
                                }
                            }
                        }
                    }
                    .fileActions(selection: $selection) { urls[$0] }
                    .frame(minHeight: 80)
                    if let selected, FileKind.isImage(selected.file.path) {
                        ImageDiffView(group: selected.group, file: selected.file)
                            .frame(minHeight: 80)
                    } else {
                        DiffTextView(file: selected?.file)
                            .frame(minHeight: 80)
                    }
                }
            }
        }
    }

    private static func tag(_ group: ChangeGroup, _ file: FileDiff) -> String { "\(group.title)|\(file.path)" }

    /// Git olmayan klasörde dokunulan dosyanın yolu (tool'lar genelde mutlak yol verir).
    private static func url(of path: String, in cwd: String) -> URL {
        URL(fileURLWithPath: path.hasPrefix("/") ? path : (cwd as NSString).appendingPathComponent(path))
    }

    /// Seçili dosya; seçim yoksa ya da artık listede değilse ilk dosya.
    private func selectedFile(in groups: [ChangeGroup]) -> (tag: String, group: ChangeGroup, file: FileDiff)? {
        let all = groups.flatMap { group in group.files.map { (tag: Self.tag(group, $0), group: group, file: $0) } }
        return all.first { $0.tag == selection } ?? all.first
    }
}

private extension View {
    /// Dosya listesi: boşluk Quick Look, çift tık varsayılan uygulamayla açar, sağ tık menüsünde Finder ve yol kopyalama.
    func fileActions(selection: Binding<String?>, url: @escaping (String) -> URL?) -> some View {
        contextMenu(forSelectionType: String.self) { tags in
            if let tag = tags.first, let url = url(tag) { FileActions.menu(for: url) }
        } primaryAction: { tags in
            if let tag = tags.first, let url = url(tag), FileActions.exists(url) { FileActions.open(url) }
        }
        .onKeyPress(.space) {
            guard let tag = selection.wrappedValue, let url = url(tag), FileActions.exists(url) else { return .ignored }
            QuickLook.shared.toggle([url])
            return .handled
        }
    }
}

/// Dosya satırı: ikon, kalın ad, soluk klasör yolu, +/- sayıları ve renkli durum harfi.
private struct FileRow: View {
    let path: String
    let detail: FileDiff?

    var body: some View {
        let name = (path as NSString).lastPathComponent
        let folder = (path as NSString).deletingLastPathComponent
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(for: .init(filenameExtension: (name as NSString).pathExtension) ?? .data))
                .resizable().frame(width: 14, height: 14)
            Text(name).fontWeight(.medium).lineLimit(1)
            Text(folder).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            Spacer(minLength: 4)
            if let detail {
                if detail.additions > 0 { Text(verbatim: "+\(detail.additions)").font(.caption.monospaced()).foregroundStyle(.green) }
                if detail.deletions > 0 { Text(verbatim: "−\(detail.deletions)").font(.caption.monospaced()).foregroundStyle(.red) }
                Text(letter(detail.change)).font(.caption.bold().monospaced()).foregroundStyle(color(detail.change))
                    .frame(width: 12)
            }
        }
        .help(path)
        .contentShape(Rectangle())
    }

    private func letter(_ change: FileDiff.Change) -> String {
        switch change {
        case .modified: "M"
        case .added: "A"
        case .deleted: "D"
        case .renamed: "R"
        }
    }

    private func color(_ change: FileDiff.Change) -> Color {
        switch change {
        case .modified: .orange
        case .added: .green
        case .deleted: .red
        case .renamed: .purple
        }
    }
}

/// Seçili dosyanın diff'i: tek bir NSTextView ve attributed string; binlerce satırda da hızlı, seçilebilir.
struct DiffTextView: NSViewRepresentable {
    let file: FileDiff?

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.isSelectable = true
            text.drawsBackground = false
            text.textContainerInset = NSSize(width: 6, height: 6)
            text.isHorizontallyResizable = true
            text.textContainer?.widthTracksTextView = false
            text.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        let signature = file.map { "\($0.path)#\($0.hunks.count)#\($0.additions)#\($0.deletions)" }
        guard context.coordinator.signature != signature else { return }
        context.coordinator.signature = signature
        text.textStorage?.setAttributedString(Self.render(file))
        text.scrollToBeginningOfDocument(nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var signature: String?
    }

    static func render(_ file: FileDiff?) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let output = NSMutableAttributedString()
        func append(_ line: String, color: NSColor, background: NSColor? = nil) {
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            if let background { attributes[.backgroundColor] = background }
            output.append(NSAttributedString(string: line + "\n", attributes: attributes))
        }
        guard let file else {
            append(String(localized: "Select a file."), color: .secondaryLabelColor)
            return output
        }
        if file.isBinary { append(String(localized: "Binary file"), color: .secondaryLabelColor); return output }
        if file.hunks.isEmpty { append(String(localized: "No content, or the diff is too large."), color: .secondaryLabelColor); return output }
        for hunk in file.hunks {
            append(hunk.header, color: .secondaryLabelColor)
            for line in hunk.lines {
                switch line.kind {
                case .added: append("+" + line.text, color: .systemGreen, background: .systemGreen.withAlphaComponent(0.1))
                case .removed: append("-" + line.text, color: .systemRed, background: .systemRed.withAlphaComponent(0.1))
                case .context: append(" " + line.text, color: .labelColor)
                }
            }
        }
        return output
    }
}

/// Ajanın todo/plan listesi.
struct TodoInspector: View {
    @Bindable var model: AppModel

    var body: some View {
        if let id = model.layout.focused, let session = model.store.session(id) {
            if session.todos.isEmpty {
                ContentUnavailableView("No to-do list", systemImage: "checklist",
                                       description: Text("The to-do tool is off in this Claude Code setup. Plans from Codex sessions will appear here."))
            } else {
                List(Array(session.todos.enumerated()), id: \.offset) { _, item in
                    Label(item.title, systemImage: symbol(item.status))
                        .foregroundStyle(item.status == .done ? .secondary : .primary)
                        .fontWeight(item.status == .inProgress ? .semibold : .regular)
                }
            }
        } else {
            ContentUnavailableView("No session selected", systemImage: "checklist")
        }
    }

    private func symbol(_ status: TodoItem.Status) -> String {
        switch status {
        case .done: "checkmark.circle.fill"
        case .inProgress: "circle.dotted.circle"
        case .pending: "circle"
        }
    }
}
