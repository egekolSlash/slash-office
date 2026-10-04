import AgentOfficeCore
import SwiftUI

/// 1 terminal tam alan, 2 yan yana, 3–4 terminal 2×2 (spec §4).
struct TerminalGrid: View {
    @Bindable var model: AppModel
    let requestRemove: (String) -> Void

    var body: some View {
        let ids = model.layout.visible
        if ids.isEmpty {
            ContentUnavailableView("Terminal açık değil", systemImage: "terminal",
                                   description: Text("Ofisten bir ajana tıkla ya da ⌘N ile yeni oturum başlat."))
        } else {
            let columns = model.layout.columns
            VStack(spacing: 2) {
                ForEach(Array(stride(from: 0, to: ids.count, by: columns)), id: \.self) { start in
                    HStack(spacing: 2) {
                        ForEach(ids[start..<min(start + columns, ids.count)], id: \.self) { id in
                            TerminalPane(model: model, id: id, requestRemove: requestRemove)
                        }
                    }
                }
            }
        }
    }
}
