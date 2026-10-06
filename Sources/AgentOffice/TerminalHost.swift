import AgentOfficeCore
import AppKit
import SwiftTerm
import SwiftUI

/// Odak bilgisini modelle eşleyen terminal: tıklanıp klavyeyi aldığında haber verir, odak istendiğinde
/// henüz pencereye yerleşmemişse yerleştiği anda klavyeyi alır.
final class AgentTerminalView: LocalProcessTerminalView {
    var onFocus: (() -> Void)?
    var wantsKeyboard = false
    /// SwiftTerm `becomeFirstResponder`'ı ezmeye izin vermiyor; pencerenin ilk yanıtlayıcısı izlenir.
    private var responderObservation: NSKeyValueObservation?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        responderObservation = window?.observe(\.firstResponder, options: [.new]) { [weak self] window, _ in
            MainActor.assumeIsolated {
                guard let self, window.firstResponder === self else { return }
                DebugLog.write("terminal became first responder")
                self.onFocus?()
            }
        }
        if wantsKeyboard { takeKeyboard() }
    }

    /// Claude'un arayüzü fare raporlamasını açtığında SwiftTerm tıklamayı programa iletip döner ve terminali
    /// odaklamaz; tıklanan terminal klavyeyi alsın diye önce odak verilir.
    override func mouseDown(with event: NSEvent) {
        DebugLog.write("terminal mouseDown, firstResponder=\(window?.firstResponder === self)")
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        super.mouseDown(with: event)
    }

    /// Ghostty'nin macOS kısayolları: SwiftTerm ⌘⌫'yu yutuyor, ⌘←/→'yu kelime atlamaya çeviriyor; Option Meta
    /// değilken ⌥⌫ ve ⌥←/→ hiçbir şey göndermiyor. Readline/Claude karşılıkları ham bayt olarak gönderilir.
    /// SwiftTerm `keyDown`'ı ezmeye izin vermiyor; tuşlar önce `performKeyEquivalent`'ten geçtiği için burada yakalanır.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        if event.type == .keyDown, window?.firstResponder === self,
           let bytes = Self.shortcutBytes(flags: flags, keyCode: event.keyCode) {
            send(bytes)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private static func shortcutBytes(flags: NSEvent.ModifierFlags, keyCode: UInt16) -> [UInt8]? {
        switch (flags, keyCode) {
        case (.command, 51): [0x15] // ⌘⌫: satırın başına kadar sil (Ctrl-U)
        case (.command, 117): [0x0b] // ⌘⌦: satırın sonuna kadar sil (Ctrl-K)
        case (.command, 123): [0x01] // ⌘←: satır başı (Ctrl-A)
        case (.command, 124): [0x05] // ⌘→: satır sonu (Ctrl-E)
        case (.option, 51): [0x1b, 0x7f] // ⌥⌫: önceki kelimeyi sil
        case (.option, 123): [0x1b, 0x62] // ⌥←: kelime geri (ESC b)
        case (.option, 124): [0x1b, 0x66] // ⌥→: kelime ileri (ESC f)
        default: nil
        }
    }

    /// Ghostty'den okunan font, renkler ve Option davranışı.
    func apply(_ appearance: TerminalAppearance, fontSize: Double) {
        font = Self.font(family: appearance.fontFamily, size: fontSize)
        nativeBackgroundColor = appearance.background.nsColor
        nativeForegroundColor = appearance.foreground.nsColor
        installColors(appearance.palette.map { SwiftTerm.Color(red8: UInt16($0.red), green8: UInt16($0.green), blue8: UInt16($0.blue)) })
        if let cursor = appearance.cursor { caretColor = cursor.nsColor }
        caretTextColor = appearance.cursorText?.nsColor
        if let selection = appearance.selectionBackground { selectedTextBackgroundColor = selection.nsColor }
        optionAsMetaKey = appearance.optionAsAlt
        // Ghostty'de bold-is-bright varsayılan kapalı.
        useBrightColors = false
    }

    /// Ghostty'nin font-family'si, yoksa Ghostty'nin varsayılanı JetBrains Mono, o da kurulu değilse SF Mono.
    private static func font(family: String?, size: Double) -> NSFont {
        for name in [family, "JetBrains Mono"].compactMap({ $0 }) {
            if let font = NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size) { return font }
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // MARK: - Sürükle-bırak (Ghostty gibi): bırakılan dosyaların yolu yazılır, Claude onları referans alır.

    private var dropRegistered = false

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if !dropRegistered {
            registerForDraggedTypes([.fileURL])
            dropRegistered = true
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.droppedPaths(sender).isEmpty ? [] : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.droppedPaths(sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let paths = Self.droppedPaths(sender)
        guard !paths.isEmpty else { return false }
        let text = DropText.text(forPaths: paths)
        // Uygulama bracketed paste istiyorsa yapıştırma olarak gönder (Claude görselleri böyle tanır).
        if getTerminal().bracketedPasteMode {
            send(txt: "\u{1b}[200~" + text + "\u{1b}[201~")
        } else {
            send(txt: text)
        }
        window?.makeFirstResponder(self)
        onFocus?()
        return true
    }

    private static func droppedPaths(_ sender: NSDraggingInfo) -> [String] {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return (urls ?? []).map(\.path)
    }

    func takeKeyboard() {
        guard let window, window.firstResponder !== self else { return }
        window.makeFirstResponder(self)
    }
}

/// Model'in sahip olduğu terminal view'ını gösterir. View, seçim değişince yok olmaz.
struct TerminalHost: NSViewRepresentable {
    let terminal: AgentTerminalView

    func makeNSView(context: Context) -> AgentTerminalView { terminal }
    func updateNSView(_ nsView: AgentTerminalView, context: Context) {}
}

extension RGB {
    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}
