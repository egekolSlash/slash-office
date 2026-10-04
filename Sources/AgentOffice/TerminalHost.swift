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
