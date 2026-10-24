import AgentOfficeCore
import SwiftUI

struct StatusBadge: View {
    let state: AgentState
    var kind: SessionKind = .claude
    /// Tur bitse de süren arka plan işleri (subagent, arka plan komutu).
    var background: [BackgroundJob] = []

    var body: some View {
        HStack(spacing: 4) {
            Label(text, systemImage: symbol)
                .foregroundStyle(color)
            if !background.isEmpty, !idleWithBackground {
                Text("+\(background.count) in background").foregroundStyle(.teal)
            }
        }
        .font(.caption)
        .help(background.map { $0.kind == .shell ? "⌘ \($0.label)" : "✦ \($0.label)" }.joined(separator: "\n"))
    }

    /// Turu bitti ama arkada iş sürüyor: "boşta" yerine ayrı görünüm.
    private var idleWithBackground: Bool { state == .idle && !background.isEmpty }

    private var text: LocalizedStringKey {
        if idleWithBackground { return "\(background.count) in background" }
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
        if idleWithBackground { return "arrow.triangle.2.circlepath" }
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
        if idleWithBackground { return .teal }
        return switch state {
        case .waiting: .orange
        case .working: .blue
        case .exited: .secondary
        default: .gray
        }
    }
}
