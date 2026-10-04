import SwiftTerm
import SwiftUI

/// Model'in sahip olduğu terminal view'ını gösterir. View, seçim değişince yok olmaz.
struct TerminalHost: NSViewRepresentable {
    let terminal: LocalProcessTerminalView

    func makeNSView(context: Context) -> LocalProcessTerminalView { terminal }
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}
