import AgentOfficeCore
import SwiftUI

/// Projenin ikonu (resim) ya da proje türünün sembolü, yuvarlatılmış kare içinde.
/// Terminal oturumlarında sağ alt köşede terminal rozeti olur.
struct ProjectIconView: View {
    let icon: LoadedProjectIcon?
    let size: Double
    var isShell = false

    var body: some View {
        Group {
            switch icon {
            case .image(let image):
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.3))
            case nil:
                Color.black.opacity(0.2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if isShell {
                Image(systemName: "apple.terminal.fill")
                    .font(.system(size: size * 0.3, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.5, height: size * 0.5)
                    .background(.black, in: RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous).stroke(.white.opacity(0.8), lineWidth: 1))
                    .offset(x: size * 0.15, y: size * 0.15)
            }
        }
    }
}

extension ProjectPalette {
    static func color(for project: String) -> Color {
        let c = colors[index(for: project)]
        return Color(red: c.red, green: c.green, blue: c.blue)
    }
}
