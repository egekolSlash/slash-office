import AgentOfficeCore
import Foundation

/// Arayüzün kıyafet listesi: temel paket ve kurulu paketlerin öğeleri.
struct WardrobeCatalog: Equatable {
    struct Entry: Equatable, Identifiable {
        var id: String
        var title: String?
        var onepiece: Bool
        var design: Bool
        /// Tasarımın kendi iki rengi (sRGB).
        var colors: [[Float]]?
        /// Paket kimliği (temel öğede nil).
        var pack: String?
    }

    var tops: [Entry] = []
    var bottoms: [Entry] = []
    var shoes: [Entry] = []

    init() {}

    init(art: CharacterArt) {
        func entries(_ items: [CharacterArt.Item]) -> [Entry] {
            items.map { item in
                let mesh = item.parts.first?.mesh ?? ""
                let pack = mesh.contains(":") ? String(mesh[..<mesh.firstIndex(of: ":")!]) : nil
                let colors = item.parts.first { $0.mode == .design }?.colors
                return Entry(id: item.name, title: item.title(language: Locale.current.language.languageCode?.identifier),
                             onepiece: item.onepiece == true, design: item.isDesign, colors: colors,
                             pack: pack)
            }
        }
        tops = entries(art.outfits)
        bottoms = entries(art.bottoms)
        shoes = entries(art.shoes)
    }

    func top(_ id: String) -> Entry? { tops.first { $0.id == id } }
}

/// İndirilebilir paketler: liste, indirme (SHA-256 doğrulamalı), kaldırma; değişince ofis kataloğu yenilenir.
extension AppModel {
    var packCatalog: [PackInfo] {
        let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = Bundle.main.url(forResource: "packs", withExtension: "json")
            ?? repoRoot.appendingPathComponent("Resources/packs.json")
        return PackStore.catalog(at: url)
    }

    /// Kurulu paketleri okur ve ofisin kataloğunu (ve arayüzün kıyafet listesini) günceller.
    func reloadPacks() async {
        let installed = PackStore.installed()
        installedPacks = Dictionary(uniqueKeysWithValues: installed.map { ($0.id, $0.version) })
        guard let gpu = await OfficeGPU.shared() else { return }
        let packs = installed.map { ($0.id, $0.directory) }
        await Task.detached(priority: .userInitiated) { gpu.character.setPacks(packs) }.value
        wardrobe = WardrobeCatalog(art: gpu.character.art)
    }

    func downloadPack(_ info: PackInfo) async {
        guard !packDownloads.contains(info.id), let url = URL(string: info.url) else { return }
        packDownloads.insert(info.id)
        defer { packDownloads.remove(info.id) }
        do {
            let (file, response) = try await URLSession.shared.download(from: url)
            defer { try? FileManager.default.removeItem(at: file) }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            try await Task.detached(priority: .userInitiated) { try PackStore.install(zip: file, info: info) }.value
            await reloadPacks()
        } catch PackStore.Failure.checksum {
            errorMessage = String(localized: "The pack \(info.title) could not be verified (checksum mismatch); it was not installed.")
        } catch {
            errorMessage = String(localized: "The pack \(info.title) could not be downloaded: \(error.localizedDescription)")
        }
    }

    func removePack(_ id: String) async {
        do { try PackStore.remove(id: id) } catch {
            errorMessage = String(localized: "The pack could not be removed: \(error.localizedDescription)")
        }
        await reloadPacks()
    }
}
