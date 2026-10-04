import AgentOfficeCore
import SwiftUI

enum InspectorTab: Hashable {
    case sessions, diff, todo
}

/// Odaktaki oturumun diff'i: oturum başından beri çalışma alanında değişenler (spec §3, §4).
struct DiffInspector: View {
    @Bindable var model: AppModel

    var body: some View {
        if let id = model.layout.focused, let session = model.store.session(id) {
            VStack(alignment: .leading, spacing: 0) {
                header(session: session, state: model.diffWatcher.states[id])
                Divider()
                content(session: session, state: model.diffWatcher.states[id])
            }
            .onAppear { model.requestDiff(id, immediately: true) }
            .onChange(of: id) { _, newID in model.requestDiff(newID, immediately: true) }
        } else {
            ContentUnavailableView("Oturum seçili değil", systemImage: "doc.text.magnifyingglass")
        }
    }

    private func header(session: AgentStore.Session, state: DiffState?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(session.title).font(.headline)
                if case .ready(_, let branch?) = state {
                    Label(branch, systemImage: "arrow.triangle.branch").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.requestDiff(session.id, immediately: true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
                    .help("Diff'i yenile")
            }
            Text("Oturum başından beri çalışma alanındaki değişiklikler")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
    }

    @ViewBuilder
    private func content(session: AgentStore.Session, state: DiffState?) -> some View {
        switch state {
        case nil, .loading?:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .noRepository?:
            if session.touchedFiles.isEmpty {
                ContentUnavailableView("Git deposu değil", systemImage: "folder",
                                       description: Text("Dokunulan dosyalar burada listelenecek."))
            } else {
                List(session.touchedFiles, id: \.self) { path in
                    Label((path as NSString).lastPathComponent, systemImage: "doc").help(path)
                }
            }
        case .ready(let files, _)?:
            if files.isEmpty {
                ContentUnavailableView("Henüz değişiklik yok", systemImage: "checkmark.circle")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(files) { file in FileDiffView(file: file) }
                    }
                    .padding(8)
                }
            }
        }
    }
}

private struct FileDiffView: View {
    let file: FileDiff
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if file.isBinary {
                Text("binary dosya").font(.caption).foregroundStyle(.secondary)
            } else {
                lines
            }
        } label: {
            HStack(spacing: 6) {
                Text(changeLabel).font(.caption2.bold()).foregroundStyle(changeColor)
                Text(file.path).font(.caption.monospaced()).lineLimit(1).truncationMode(.head)
                Spacer()
                Text("+\(file.additions)").font(.caption.monospaced()).foregroundStyle(.green)
                Text("−\(file.deletions)").font(.caption.monospaced()).foregroundStyle(.red)
            }
        }
    }

    private var lines: some View {
        let all = file.hunks.flatMap { hunk in [(hunk.header, DiffLine.Kind?.none)] + hunk.lines.map { ($0.text, Optional($0.kind)) } }
        let shown = all.prefix(DiffWatcher.maxLinesPerFile)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                Text(prefix(line.1) + line.0)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(color(line.1))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(background(line.1))
                    .lineLimit(1)
            }
            if all.count > shown.count {
                Text("… \(all.count - shown.count) satır daha").font(.caption2).foregroundStyle(.secondary)
            } else if file.hunks.isEmpty, !file.isBinary {
                Text("içerik gösterilmiyor (diff çok büyük)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .textSelection(.enabled)
    }

    private var changeLabel: String {
        switch file.change {
        case .modified: "D"
        case .added: "Y"
        case .deleted: "S"
        case .renamed: "A"
        }
    }

    private var changeColor: Color {
        switch file.change {
        case .added: .green
        case .deleted: .red
        case .renamed: .purple
        case .modified: .orange
        }
    }

    private func prefix(_ kind: DiffLine.Kind?) -> String {
        switch kind {
        case .added?: "+"
        case .removed?: "−"
        case .context?: " "
        case nil: ""
        }
    }

    private func color(_ kind: DiffLine.Kind?) -> Color {
        switch kind {
        case .added?: .green
        case .removed?: .red
        case .context?: .primary
        case nil: .secondary
        }
    }

    private func background(_ kind: DiffLine.Kind?) -> Color {
        switch kind {
        case .added?: .green.opacity(0.08)
        case .removed?: .red.opacity(0.08)
        default: .clear
        }
    }
}

/// Ajanın todo/plan listesi.
struct TodoInspector: View {
    @Bindable var model: AppModel

    var body: some View {
        if let id = model.layout.focused, let session = model.store.session(id) {
            if session.todos.isEmpty {
                ContentUnavailableView("Todo listesi yok", systemImage: "checklist",
                                       description: Text("Bu Claude Code kurulumunda todo aracı kapalı. Codex oturumlarında plan burada görünecek."))
            } else {
                List(Array(session.todos.enumerated()), id: \.offset) { _, item in
                    Label(item.title, systemImage: symbol(item.status))
                        .foregroundStyle(item.status == .done ? .secondary : .primary)
                        .fontWeight(item.status == .inProgress ? .semibold : .regular)
                }
            }
        } else {
            ContentUnavailableView("Oturum seçili değil", systemImage: "checklist")
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
