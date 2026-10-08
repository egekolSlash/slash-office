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

    private var text: LocalizedStringKey {
        if kind == .shell, state == .idle || state == .starting { return "Terminal · ready" }
        return switch state {
        case .starting: "Starting"
        case .idle: "Idle"
        case .working(let tool?): "Working · \(tool)"
        case .working(nil): "Working"
        case .waiting(.permission): "Waiting for permission"
        case .waiting(.question): "Asking a question"
        case .exited: "Stopped"
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
