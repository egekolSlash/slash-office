import AgentOfficeCore
import SwiftUI

/// "Bitti, görülmedi" rozeti: çalışırken işini bitirdi, kullanıcı henüz bakmadı.
struct FinishedBadge: View {
    var compact = false

    var body: some View {
        Label(compact ? "" : String(localized: "Finished"), systemImage: "checkmark.circle.fill")
            .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.green)
            .help("Finished working; you haven't looked yet")
    }
}

/// Ofiste köylünün başının üstündeki yeşil ✓ balonu (bekleyenlerin turuncu `?`'ı gibi).
struct FinishedBubble: View {
    let size: Double

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.5, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(red: 0.25, green: 0.72, blue: 0.35)))
    }
}

struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
