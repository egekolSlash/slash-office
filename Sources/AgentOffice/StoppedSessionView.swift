import AgentOfficeCore
import SwiftUI

/// Durmuş oturumun panelinde ortada duran büyük kart: devam ettir / kaldır ve birden fazla durmuş oturum varsa
/// hepsini devam ettir. Kısayollar Ajanlar menüsünde (⌘R, ⌘⇧⌫, ⌘⇧R); düğmelerde de yazılı.
struct StoppedSessionView: View {
    @Bindable var model: AppModel
    let session: AgentStore.Session
    let requestRemove: (String) -> Void
    /// Süreci bitmiş terminalin çıktısının üstünde: yarı saydam arka plan.
    var overTerminal = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text(session.title).font(.title2.bold())
                if let summary = session.workSummary {
                    Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
                }
                Text((session.cwd as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.tertiary)
            }
            HStack(spacing: 14) {
                BigAction(title: "Devam ettir", shortcut: "⌘R", symbol: "play.fill", tint: .accentColor) {
                    model.resume(session.id)
                }
                BigAction(title: "Kaldır", shortcut: "⌘⇧⌫", symbol: "trash", tint: .red) {
                    requestRemove(session.id)
                }
            }
            let others = model.stoppedSessionIDs.count
            if others >= 2 {
                Button { model.resumeAllStopped() } label: {
                    Label("Tüm durmuş oturumları devam ettir (\(others))  ⌘⇧R", systemImage: "play.square.stack")
                }
                .buttonStyle(.link)
            }
        }
        .padding(28)
        .frame(maxWidth: 460)
        .background(overTerminal ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BigAction: View {
    let title: String
    let shortcut: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 26, weight: .semibold))
                Text(title).font(.headline)
                Text(shortcut).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            .frame(width: 150, height: 110)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.45)))
            .foregroundStyle(tint)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
