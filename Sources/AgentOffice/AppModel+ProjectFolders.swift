import AgentOfficeCore
import AppKit
import Foundation

extension AppModel {
    static let projectRootsKey = "projectRoots"

    /// Proje seçicide gösterilen liste: son projeler, ardından proje klasörlerinde bulunanlar.
    var pickerProjects: [String] {
        ProjectFolders.merged(recent: recentProjects, discovered: discoveredProjects)
    }

    /// ⇧⌘O: bir klasör seçtirir; altındaki her klasör proje olarak listelenir ve klasör izlenir.
    func addProjectRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = String(localized: "Choose a folder that holds your projects. Every folder inside it will be listed and kept up to date.")
        panel.prompt = String(localized: "Add Projects Folder")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectRoots = ProjectFolders.adding(url.path, to: projectRoots)
        UserDefaults.standard.set(projectRoots, forKey: Self.projectRootsKey)
        watchProjectRoots()
    }

    func removeProjectRoot(_ root: String) {
        projectRoots.removeAll { $0 == root }
        UserDefaults.standard.set(projectRoots, forKey: Self.projectRootsKey)
        watchProjectRoots()
    }

    /// Kökleri yeniden tarar (seçici her açıldığında ve kökte bir şey eklenip silinince).
    func rescanProjectRoots() {
        let found = ProjectFolders.scan(roots: projectRoots)
        guard found != discoveredProjects else { return }
        DebugLog.write("project roots: \(found.count) projects")
        discoveredProjects = found
    }

    /// Her kök için klasör izleyicisi: içine klasör eklenince, silinince ya da adı değişince yeniden taranır.
    func watchProjectRoots() {
        for (root, source) in rootWatchers where !projectRoots.contains(root) {
            source.cancel()
            rootWatchers[root] = nil
        }
        for root in projectRoots where rootWatchers[root] == nil {
            let descriptor = open(root, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Kökün kendisi silinir ya da taşınırsa izleyici yeniden kurulur (aynı yolda yeniden oluşursa).
                    if let source = self.rootWatchers[root], !source.data.intersection([.rename, .delete]).isEmpty {
                        source.cancel()
                        self.rootWatchers[root] = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated { self.watchProjectRoots() } }
                    }
                    self.rescanProjectRoots()
                }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            rootWatchers[root] = source
        }
        rescanProjectRoots()
    }
}
