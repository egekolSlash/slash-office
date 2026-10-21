import AgentOfficeCore
import AppKit
import SwiftTerm
import SwiftUI

/// Odak bilgisini modelle eşleyen terminal: tıklanıp klavyeyi aldığında haber verir, odak istendiğinde
/// henüz pencereye yerleşmemişse yerleştiği anda klavyeyi alır.
final class AgentTerminalView: LocalProcessTerminalView {
    var onFocus: (() -> Void)?
    var wantsKeyboard = false
    /// Oturumun klasörü: terminaldeki göreli yollar buna göre çözülür.
    var directory: String?
    /// SwiftTerm `becomeFirstResponder`'ı ezmeye izin vermiyor; pencerenin ilk yanıtlayıcısı izlenir.
    private var responderObservation: NSKeyValueObservation?
    private var windowObservers: [NSObjectProtocol] = []
    /// SwiftTerm `scrollWheel`'i ezmeye izin vermiyor; bu terminalin üstündeki kaydırmalar yerel dinleyiciyle izlenir.
    private var scrollMonitor: Any?
    private var lastScroll: Date?

    isolated deinit {
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeRedrawTriggers()
        observeScrolling()
        responderObservation = window?.observe(\.firstResponder, options: [.new]) { [weak self] window, _ in
            MainActor.assumeIsolated {
                // Klavyeyi alan terminal biriken değişiklikleri hemen göstersin.
                self?.flushDeferredDisplay()
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

    /// ⌘-tıklanan yol (SwiftTerm ⌘ basılıyken yolların altını çizer): ⌘ Quick Look, ⇧⌘ Finder'da gösterir.
    /// Web adresleri eskisi gibi tarayıcıda açılır.
    override func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        let fileURL: URL?
        if let url = URL(string: link), let scheme = url.scheme {
            guard scheme == "file" else { return super.requestOpenLink(source: source, link: link, params: params) }
            fileURL = FileManager.default.fileExists(atPath: url.path) ? url : nil
        } else {
            fileURL = FileKind.resolve(firstOf: linkCandidates(link), relativeTo: directory)
        }
        guard let fileURL else { return }
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            FileActions.reveal(fileURL)
        } else {
            QuickLook.shared.toggle([fileURL])
        }
    }

    /// SwiftTerm'in eşleşmesi yolun ardındaki metni de içerebilir; tıklanan hücrenin satırı ve biçimi de verilir.
    /// Hücre boyutu SwiftTerm'de gizli: genişlik onun gibi fontun "W" genişliğinden (piksele yuvarlanmış), yükseklik
    /// `getOptimalFrameSize`'ın satır sayısına bölünmesinden bulunur.
    private func linkCandidates(_ link: String) -> [String] {
        let terminal = getTerminal()
        guard let event = NSApp.currentEvent, terminal.rows > 0 else { return [link] }
        let scale = window?.backingScaleFactor ?? 2
        let cellWidth = max(1, (font.advancement(forGlyph: font.glyph(withName: "W")).width * scale).rounded() / scale)
        let cellHeight = getOptimalFrameSize().height / CGFloat(terminal.rows)
        let point = convert(event.locationInWindow, from: nil)
        let column = Int(point.x / cellWidth)
        let row = Int((frame.height - point.y) / cellHeight)
        guard let line = terminal.getLine(row: row) else {
            return TerminalLink.candidates(cells: [(character: Character, style: Int)](), column: 0, link: link)
        }
        // Boş hücre (kod 0) bir yazının hemen ardındaysa geniş karakterin devamıdır, atlanır; değilse boşluktur.
        // Tıklanan sütun dizideki yerine çevrilir.
        var cells: [(character: Character, style: Attribute)] = []
        var clicked = 0
        for col in 0..<min(terminal.cols, line.count) {
            let data = line[col]
            let isEmpty = data.getCharacter() == "\0"
            if isEmpty, let last = cells.last, !last.character.isWhitespace, col > 0, line[col - 1].getCharacter() != "\0" { continue }
            if col <= column { clicked = cells.count }
            cells.append((character: isEmpty ? " " : terminal.getCharacter(for: data), style: data.attribute))
        }
        return TerminalLink.candidates(cells: cells, column: clicked, link: link)
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

    // MARK: - Seyrek çizim (`TerminalRedraw`)

    /// Bekleyen (henüz çizdirilmemiş) bölge.
    private var deferredDirty: NSRect?
    private var flushScheduled = false
    private var flushing = false

    /// nil: hemen çiz. Klavyesi olan terminal hemen, diğerleri ve arka plandaki uygulama seyrek çizer.
    private var redrawInterval: TimeInterval? {
        guard let window, !inLiveResize else { return nil }
        return TerminalRedraw.interval(focused: window.isKeyWindow && window.firstResponder === self, appActive: NSApp.isActive,
                                       energySaving: OfficeMetalView.energySavingEnabled,
                                       scrolling: TerminalRedraw.isScrolling(lastScroll: lastScroll, now: Date()))
    }

    /// Kaydırma başlarken biriken değişiklikler hemen gösterilir; kaydırma süresince terminal hemen çizer.
    private func observeScrolling() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        guard window != nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return }
                self.lastScroll = Date()
                self.flushDeferredDisplay()
            }
            return event
        }
    }

    /// SwiftTerm her değişiklikte değişen satırları buradan çizdirir; seyrek çizilen terminalde bölgeler birleştirilip
    /// aralık dolunca bir kez çizdirilir.
    override func setNeedsDisplay(_ invalidRect: NSRect) {
        guard !flushing, let interval = redrawInterval else { return super.setNeedsDisplay(invalidRect) }
        deferredDirty = deferredDirty.map { $0.union(invalidRect) } ?? invalidRect
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            MainActor.assumeIsolated { self?.flushDeferredDisplay() }
        }
    }

    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set {
            if newValue, !flushing, redrawInterval != nil { setNeedsDisplay(bounds) } else { super.needsDisplay = newValue }
        }
    }

    /// Bekleyen bölgeyi çizdirir. Pencere görünmüyorsa (başka pencerenin altında, küçültülmüş) bekletir; görününce çizilir.
    private func flushDeferredDisplay() {
        flushScheduled = false
        guard let rect = deferredDirty, window?.occlusionState.contains(.visible) == true else { return }
        deferredDirty = nil
        flushing = true
        super.setNeedsDisplay(rect)
        flushing = false
    }

    private func observeRedrawTriggers() {
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers = []
        guard let window else { return }
        let triggers: [(Notification.Name, AnyObject?)] = [
            (NSApplication.didBecomeActiveNotification, nil), (NSWindow.didBecomeKeyNotification, window),
            (NSWindow.didChangeOcclusionStateNotification, window),
        ]
        for (name, object) in triggers {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.flushDeferredDisplay() }
            })
        }
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
