import AgentOfficeCore
import SwiftUI

struct StatusBadge: View {
    let state: AgentState

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(color)
    }

    private var text: String {
        switch state {
        case .starting: "Başlıyor"
        case .idle: "Boşta"
        case .working(let tool?): "Çalışıyor · \(tool)"
        case .working(nil): "Çalışıyor"
        case .waiting(.permission): "İzin bekliyor"
        case .waiting(.question): "Soru soruyor"
        case .exited: "Kapandı"
        }
    }

    private var symbol: String {
        switch state {
        case .starting: "hourglass"
        case .idle: "moon.zzz"
        case .working: "keyboard"
        case .waiting: "questionmark.bubble.fill"
        case .exited: "xmark.circle"
        }
    }

    private var color: Color {
        switch state {
        case .waiting: .orange
        case .working: .blue
        case .exited: .secondary
        default: .gray
        }
    }
}
