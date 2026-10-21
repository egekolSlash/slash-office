import AgentOfficeCore
import AppKit
import SwiftUI

/// Oturum satırındaki dosya düğmesi: oturumda değiştirilen, okunan ve sohbette adı geçen dosyalar.
/// Liste her açılışta kayıt dosyasından yeniden okunur.
struct SessionFilesButton: View {
    let model: AppModel
    let sessionID: String
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(showing ? Color.accentColor : .secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Files in this session")
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            SessionFilesList(model: model, sessionID: sessionID)
        }
    }
}

private struct SessionFilesList: View {
    let model: AppModel
    let sessionID: String
    @State private var files: [SessionFile]?
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Files in this session").font(.headline).padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 6)
            if let files {
                if files.isEmpty {
                    ContentUnavailableView("No files yet", systemImage: "doc",
                                           description: Text("Files the agent edits, reads or mentions will be listed here."))
                } else {
                    list(files)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 440, height: 360)
        .task { files = await model.sessionFiles(sessionID) }
    }

    private func list(_ files: [SessionFile]) -> some View {
        let cwd = model.store.session(sessionID)?.cwd ?? ""
        let urls = Dictionary(files.map { ($0.path, URL(fileURLWithPath: $0.path)) }) { first, _ in first }
        return List(selection: $selection) {
            ForEach([SessionFile.Kind.edited, .read, .mentioned], id: \.self) { kind in
                let group = files.filter { $0.kind == kind }
                if !group.isEmpty {
                    Section(String("\(title(kind)) · \(group.count)")) {
                        ForEach(group) { file in
                            HStack(spacing: 4) {
                                FileRow(path: Self.display(file.path, in: cwd), detail: nil)
                                rowButton("eye", "Quick Look") { QuickLook.shared.show([URL(fileURLWithPath: file.path)]) }
                                rowButton("folder", "Show in Finder") { FileActions.reveal(URL(fileURLWithPath: file.path)) }
                            }
                            .tag(file.path)
                        }
                    }
                }
            }
        }
        .fileActions(selection: $selection) { urls[$0] }
    }

    private func rowButton(_ symbol: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 18, height: 18).contentShape(Rectangle()) }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel(label)
    }

    private func title(_ kind: SessionFile.Kind) -> String {
        switch kind {
        case .edited: String(localized: "Edited")
        case .read: String(localized: "Read")
        case .mentioned: String(localized: "Mentioned")
        }
    }

    /// Proje içindeki dosya göreli, dışındaki `~` ile kısaltılmış gösterilir.
    static func display(_ path: String, in cwd: String) -> String {
        if !cwd.isEmpty, path.hasPrefix(cwd + "/") { return String(path.dropFirst(cwd.count + 1)) }
        return (path as NSString).abbreviatingWithTildeInPath
    }
}

/// Satırın sağ kenarındaki aktiflik şeridi: oturumlar arasında en az boşta kalan sıcak, en çok boşta kalan soğuk renkte.
struct ActivityStripe: View {
    let level: Double

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Self.color(level))
            .frame(width: 4)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    /// Gri → camgöbeği → sarı → turuncu-kırmızı.
    static func color(_ level: Double) -> Color {
        let stops: [Color] = [.gray.opacity(0.25), .teal, .yellow, Color(red: 1, green: 0.35, blue: 0.2)]
        let position = min(max(level, 0), 1) * Double(stops.count - 1)
        let index = min(Int(position), stops.count - 2)
        return stops[index].mix(with: stops[index + 1], by: position - Double(index))
    }
}
