import AgentOfficeCore
import AppKit
import Quartz
import SwiftUI

/// Finder'daki boşluk tuşu gibi Quick Look paneli: aynı dosyalar için ikinci çağrı paneli kapatır.
@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLook()
    private var urls: [URL] = []

    func toggle(_ urls: [URL]) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible, urls == self.urls {
            panel.orderOut(nil)
            return
        }
        show(urls)
    }

    func show(_ urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }
}

/// Dosya için Finder ve uygulama işlemleri.
@MainActor
enum FileActions {
    /// Dosyayı Finder'da seçili gösterir; dosya silinmişse var olan en yakın üst klasörü açar.
    static func reveal(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        var folder = url.deletingLastPathComponent()
        while folder.path != "/", !FileManager.default.fileExists(atPath: folder.path) { folder = folder.deletingLastPathComponent() }
        NSWorkspace.shared.open(folder)
    }

    static func open(_ url: URL) { NSWorkspace.shared.open(url) }

    static func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Dosya listelerindeki sağ tık menüsü.
    @ViewBuilder
    static func menu(for url: URL) -> some View {
        let exists = exists(url)
        Button("Quick Look") { QuickLook.shared.show([url]) }.disabled(!exists)
        Button("Open") { open(url) }.disabled(!exists)
        Button("Show in Finder") { reveal(url) }
        Divider()
        Button("Copy Path") { copyPath(url) }
    }
}

/// Değişen resmin önce/sonra hali yan yana. Eski hal git'ten (`before` sürümü), yeni hal index'ten ya da diskten okunur.
struct ImageDiffView: View {
    let group: ChangeGroup
    let file: FileDiff
    @State private var images: (before: NSImage?, after: NSImage?)?

    var body: some View {
        HStack(spacing: 8) {
            if let images {
                if hasBefore { side("Before", images.before) }
                if hasAfter { side("After", images.after) }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
        .task(id: key) { await load() }
    }

    private var hasBefore: Bool { file.change != .added }
    private var hasAfter: Bool { file.change != .deleted }
    private var key: String { "\(group.root)|\(group.before)|\(group.after ?? "-")|\(file.path)|\(file.additions)|\(file.deletions)" }

    private var beforePath: String {
        if case .renamed(let from) = file.change { return from }
        return file.path
    }

    private func side(_ title: LocalizedStringKey, _ image: NSImage?) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Group {
                if let image {
                    Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
                        .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                        .background(Checkerboard())
                } else {
                    Image(systemName: "photo.badge.exclamationmark").font(.title).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let image, let rep = image.representations.first, rep.pixelsWide > 0 {
                Text(verbatim: "\(rep.pixelsWide)×\(rep.pixelsHigh)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        images = nil
        let group = group, file = file, beforePath = beforePath, hasBefore = hasBefore, hasAfter = hasAfter
        let data = await Task.detached(priority: .userInitiated) { () -> (Data?, Data?) in
            let workspace = GitWorkspace(directory: group.root)
            let before = hasBefore ? workspace.contents(of: beforePath, at: group.before) : nil
            var after: Data?
            if hasAfter {
                if let revision = group.after {
                    after = workspace.contents(of: file.path, at: revision)
                } else {
                    after = try? Data(contentsOf: group.url(of: file))
                }
            }
            return (before, after)
        }.value
        guard !Task.isCancelled else { return }
        images = (data.0.flatMap(NSImage.init(data:)), data.1.flatMap(NSImage.init(data:)))
    }
}

/// Saydam resimlerin arkasındaki dama deseni.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            for row in 0..<Int((size.height / cell).rounded(.up)) {
                for column in 0..<Int((size.width / cell).rounded(.up)) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                 with: .color(.gray.opacity(0.18)))
                }
            }
        }
    }
}
