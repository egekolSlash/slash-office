import Foundation

/// 0–255 aralığında bir RGB rengi (`#rrggbb`).
public struct RGB: Equatable, Sendable {
    public var red: UInt8, green: UInt8, blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: UInt8(value >> 16 & 0xff), green: UInt8(value >> 8 & 0xff), blue: UInt8(value & 0xff))
    }
}

/// Terminalin görünümü: Ghostty'nin config'i ve teması, eksik kalanlar Catppuccin Mocha.
public struct TerminalAppearance: Equatable, Sendable {
    public var fontFamily: String?
    public var fontSize: Double = 14
    public var palette: [RGB] = TerminalAppearance.mochaPalette
    public var background = RGB(hex: "#1e1e2e")!
    public var foreground = RGB(hex: "#cdd6f4")!
    public var cursor: RGB? = RGB(hex: "#f5e0dc")
    public var cursorText: RGB? = RGB(hex: "#1e1e2e")
    public var selectionBackground: RGB? = RGB(hex: "#585b70")
    /// Ghostty'de varsayılan kapalı: Option, Türkçe klavyede @ # € gibi karakterleri yazar.
    public var optionAsAlt = false
    public var paddingX: Double = 2
    public var paddingY: Double = 2

    public init() {}

    static let mochaPalette: [RGB] = [
        "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8",
        "#585b70", "#f37799", "#89d88b", "#ebd391", "#74a8fc", "#f2aede", "#6bd7ca", "#bac2de",
    ].map { RGB(hex: $0)! }
}

/// Ghostty config dosyalarını (`anahtar = değer` satırları) okur.
public enum GhosttyConfig {
    /// Satırları sırasıyla döndürür; `palette` ve `font-family` gibi anahtarlar tekrar edebilir.
    public static func entries(_ text: String) -> [(key: String, value: String)] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { return nil }
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
            var value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            return key.isEmpty ? nil : (key, value)
        }
    }

    /// `theme = light:X,dark:Y` biçiminde koyu olan seçilir (uygulama koyu temalı).
    public static func themeName(_ value: String) -> String {
        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if let dark = parts.first(where: { $0.hasPrefix("dark:") }) { return String(dark.dropFirst(5)) }
        if let first = parts.first, let colon = first.firstIndex(of: ":") { return String(first[first.index(after: colon)...]) }
        return value
    }

    /// Kullanıcının config'i önce temayı, sonra kendi satırlarını uygular (Ghostty'deki öncelik).
    public static func appearance(config: String?, loadTheme: (String) -> String?) -> TerminalAppearance {
        var appearance = TerminalAppearance()
        let configEntries = entries(config ?? "")
        if let theme = configEntries.last(where: { $0.key == "theme" }), let text = loadTheme(themeName(theme.value)) {
            apply(entries(text), to: &appearance)
        }
        apply(configEntries, to: &appearance)
        return appearance
    }

    static func apply(_ entries: [(key: String, value: String)], to appearance: inout TerminalAppearance) {
        for (key, value) in entries {
            switch key {
            case "font-family": appearance.fontFamily = value.isEmpty ? nil : (appearance.fontFamily ?? value)
            case "font-size": if let size = Double(value), size > 0 { appearance.fontSize = size }
            case "background": if let color = RGB(hex: value) { appearance.background = color }
            case "foreground": if let color = RGB(hex: value) { appearance.foreground = color }
            case "cursor-color": appearance.cursor = RGB(hex: value)
            case "cursor-text": appearance.cursorText = RGB(hex: value)
            case "selection-background": appearance.selectionBackground = RGB(hex: value)
            case "macos-option-as-alt": appearance.optionAsAlt = ["true", "left", "right"].contains(value)
            case "window-padding-x": if let x = Double(value.split(separator: ",").first ?? "") { appearance.paddingX = x }
            case "window-padding-y": if let y = Double(value.split(separator: ",").first ?? "") { appearance.paddingY = y }
            case "palette":
                let parts = value.split(separator: "=", maxSplits: 1)
                if parts.count == 2, let index = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                   (0..<16).contains(index), let color = RGB(hex: String(parts[1])) {
                    appearance.palette[index] = color
                }
            default: break
            }
        }
    }

    /// Ghostty'nin config ve tema dosyalarını diskten okur; Ghostty yoksa varsayılan görünüm döner.
    public static func load(home: String = NSHomeDirectory(),
                            ghosttyApp: String = "/Applications/Ghostty.app") -> TerminalAppearance {
        let configPaths = ["\(home)/.config/ghostty/config",
                           "\(home)/Library/Application Support/com.mitchellh.ghostty/config"]
        let config = configPaths.compactMap { try? String(contentsOfFile: $0, encoding: .utf8) }.joined(separator: "\n")
        let themeDirectories = ["\(home)/.config/ghostty/themes", "\(ghosttyApp)/Contents/Resources/ghostty/themes"]
        return appearance(config: config) { name in
            themeDirectories.lazy.compactMap { try? String(contentsOfFile: "\($0)/\(name)", encoding: .utf8) }.first
        }
    }
}
