import AgentOfficeCore
import Carbon
import Foundation
import Observation
import SwiftUI

/// Geçerli klavye düzeni: adı ve bir karakterin bu düzende hangi tuşla yazıldığı. Rehberdeki kısayol tablosu
/// kısayolları kullanıcının klavyesinde göründüğü gibi gösterir; düzen değişince güncellenir.
@MainActor
@Observable
final class KeyboardLayout {
    static let shared = KeyboardLayout()

    private(set) var name = ""
    /// Karakter → (değiştiriciler, değiştiricisiz tuşun yazdığı). Tuş takımı hariç.
    private var typing: [Character: (modifiers: Shortcut.Modifiers, base: String)] = [:]

    private init() {
        reload()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { KeyboardLayout.shared.reload() }
        }
    }

    /// Kısayolun bu düzendeki gösterimi: karakter Shift/Option istiyorsa nasıl yazılacağı da eklenir ("⌘+ (⇧4)").
    func display(_ shortcut: Shortcut) -> String {
        guard case .character(let c) = shortcut.key, let how = typing[c], !how.modifiers.isEmpty else {
            return shortcut.symbols
        }
        return "\(shortcut.symbols)  (\(Shortcut.modifierSymbols(how.modifiers))\(how.base.uppercased()))"
    }

    func reload() {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return }
        if let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            name = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        }
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { typing = [:]; return }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var table: [Character: (Shortcut.Modifiers, String)] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            func translate(_ code: Int, _ modifiers: Int) -> String {
                var dead: UInt32 = 0, length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), UInt32(modifiers), UInt32(LMGetKbdType()),
                               OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
                return String(utf16CodeUnits: chars, count: length)
            }
            let states: [(Shortcut.Modifiers, Int)] = [([], 0), (.shift, shiftKey >> 8), (.option, optionKey >> 8),
                                                       ([.option, .shift], (optionKey | shiftKey) >> 8)]
            for (modifiers, state) in states {
                // Tuş takımı (65–92) hariç: dizüstünde yok.
                for code in 0..<128 where !(65...92).contains(code) {
                    let typed = translate(code, state)
                    guard typed.count == 1, let c = typed.first, table[c] == nil else { continue }
                    table[c] = (modifiers, translate(code, 0))
                }
            }
        }
        typing = table
    }
}

extension Shortcut {
    /// SwiftUI kısayolu.
    var keyboardShortcut: KeyboardShortcut {
        let equivalent: KeyEquivalent = switch key {
        case .character(let c): KeyEquivalent(c)
        case .left: .leftArrow
        case .right: .rightArrow
        case .up: .upArrow
        case .down: .downArrow
        case .delete: .delete
        }
        var flags: SwiftUI.EventModifiers = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return KeyboardShortcut(equivalent, modifiers: flags)
    }
}

extension View {
    /// Tablodaki kısayolu bağlar.
    func shortcut(_ id: String) -> some View {
        keyboardShortcut(ShortcutCatalog.shortcut(id).keyboardShortcut)
    }
}
