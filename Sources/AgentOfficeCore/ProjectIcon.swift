import Foundation

/// Bir projenin ikonu: projede bulunan bir resim dosyası, yoksa proje türünü anlatan bir sembol.
public enum ProjectIcon: Equatable, Sendable {
    case image(path: String)
    case kind(ProjectKind)
}

public enum ProjectKind: String, Equatable, Sendable {
    case unity, swift, web, android, generic
}

/// Proje klasöründen uygulama ikonunu bulur. Disk okur; ana thread'de çağrılmamalı.
public enum ProjectIconLocator {
    public static func locate(directory: String) -> ProjectIcon {
        let fm = FileManager.default
        func exists(_ relative: String) -> Bool { fm.fileExists(atPath: "\(directory)/\(relative)") }

        if exists("ProjectSettings/ProjectSettings.asset") {
            return unityIcon(directory: directory).map { .image(path: $0) } ?? .kind(.unity)
        }
        if let path = appIconSet(directory: directory) { return .image(path: path) }
        let candidates = [
            "app/src/main/res/mipmap-xxxhdpi/ic_launcher.png", "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png",
            "public/apple-touch-icon.png", "public/icon.png", "public/logo.png", "public/favicon.png",
            "app/icon.png", "src/app/icon.png", "static/favicon.png",
            "icon.png", "logo.png", "Icon.png", "Logo.png", ".github/logo.png", "assets/icon.png", "assets/logo.png",
            "public/favicon.svg", "public/favicon.ico", "favicon.ico",
        ]
        if let found = candidates.first(where: exists) { return .image(path: "\(directory)/\(found)") }
        if exists("Package.swift") || (try? fm.contentsOfDirectory(atPath: directory))?.contains(where: { $0.hasSuffix(".xcodeproj") }) == true {
            return .kind(.swift)
        }
        if exists("build.gradle") || exists("build.gradle.kts") { return .kind(.android) }
        if exists("package.json") { return .kind(.web) }
        return .kind(.generic)
    }

    /// Player Settings'teki varsayılan ikon: `ProjectSettings.asset` guid'i verir, `.meta` dosyası resmi.
    static func unityIcon(directory: String) -> String? {
        guard let settings = try? String(contentsOfFile: "\(directory)/ProjectSettings/ProjectSettings.asset", encoding: .utf8),
              let guid = iconGUID(projectSettings: settings) else { return nil }
        let assets = URL(fileURLWithPath: directory).appendingPathComponent("Assets")
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "psd", "tga", "tif", "tiff"]
        guard let enumerator = FileManager.default.enumerator(at: assets, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles]) else { return nil }
        let needle = "guid: \(guid)"
        for case let url as URL in enumerator where url.pathExtension == "meta" {
            let image = url.deletingPathExtension()
            guard imageExtensions.contains(image.pathExtension.lowercased()),
                  let meta = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if meta.contains(needle) { return image.path }
        }
        return nil
    }

    /// `m_BuildTargetIcons` altındaki ilk ikon, yoksa platform ikonlarının ilk dokusu.
    static func iconGUID(projectSettings: String) -> String? {
        let pattern = /fileID: 2800000, guid: ([0-9a-f]{32})/
        if let start = projectSettings.range(of: "m_BuildTargetIcons:"),
           let match = projectSettings[start.upperBound...].prefix(600).firstMatch(of: pattern) {
            return String(match.1)
        }
        if let start = projectSettings.range(of: "m_BuildTargetPlatformIcons:"),
           let match = projectSettings[start.upperBound...].firstMatch(of: pattern) {
            return String(match.1)
        }
        return nil
    }

    /// Xcode projesindeki `AppIcon.appiconset` içinden en büyük PNG.
    static func appIconSet(directory: String) -> String? {
        let root = URL(fileURLWithPath: directory)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey],
                                                              options: [.skipsHiddenFiles]) else { return nil }
        var best: (path: String, size: Int)?
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > 20_000 { break }
            let name = url.lastPathComponent
            if ["node_modules", "Pods", "build", "DerivedData", "Library", ".build"].contains(name) {
                enumerator.skipDescendants()
                continue
            }
            guard url.pathExtension == "png", url.deletingLastPathComponent().lastPathComponent == "AppIcon.appiconset" else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > best?.size ?? -1 { best = (url.path, size) }
        }
        return best?.path
    }
}
