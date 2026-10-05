import AgentOfficeCore
import SwiftUI

struct StatusBadge: View {
    let state: AgentState
    var kind: SessionKind = .claude

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(color)
    }

    private var text: String {
        if kind == .shell, state == .idle || state == .starting { return "Terminal · hazır" }
        return switch state {
        case .starting: "Başlıyor"
        case .idle: "Boşta"
        case .working(let tool?): "Çalışıyor · \(tool)"
        case .working(nil): "Çalışıyor"
        case .waiting(.permission): "İzin bekliyor"
        case .waiting(.question): "Soru soruyor"
        case .exited: "Durdu"
        }
    }

    private var symbol: String {
        if kind == .shell, state == .idle || state == .starting { return "terminal" }
        return switch state {
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
