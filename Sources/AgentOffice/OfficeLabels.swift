import AgentOfficeCore
import SwiftUI

/// Karoların başlıkları, tool adları ve `?` balonu: sahnenin üstüne SwiftUI ile çizilir, hiçbir zaman örtülmez.
struct OfficeLabels: View {
    let snapshot: OfficeSnapshot
    /// Proje klasörü → ikon.
    let icons: [String: LoadedProjectIcon]

    var body: some View {
        GeometryReader { geometry in
            let size = (width: Double(geometry.size.width), height: Double(geometry.size.height))
            let camera = OfficeScene.camera(for: snapshot.grid, aspect: size.width / max(size.height, 1))
            let fontSize = Self.fontSize(viewHeight: size.height, camera: camera)
            ForEach(snapshot.tiles, id: \.placement.id) { tile in
                let origin = OfficeScene.tileOrigin(tile.placement)
                let anchor = camera.project(origin + [0, IsoCamera.labelHeight, 0], viewSize: size)
                TileLabel(tile: tile, icon: icons[tile.placement.project], fontSize: fontSize)
                    .position(x: anchor.x, y: anchor.y)
                if case .waiting = tile.state {
                    // Başlığın hemen üstünde, ekran uzayında: başlığı örtmesin.
                    QuestionBubble(size: fontSize * 1.9)
                        .position(x: anchor.x, y: anchor.y - fontSize * 2.6)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Yazı boyutu sahne ölçeğiyle büyüyüp küçülür: küçük ofiste kalabalık yapmasın.
    static func fontSize(viewHeight: Double, camera: IsoCamera) -> Double {
        min(max(viewHeight / (2 * Double(camera.scale)) * 0.13, 9), 15)
    }

    /// Tıklama için başlık kutusunun yaklaşık boyutu (ikon + iki satır: başlık ve durum).
    static func labelBox(viewHeight: Double, camera: IsoCamera) -> (width: Double, height: Double) {
        let font = fontSize(viewHeight: viewHeight, camera: camera)
        return (font * 9, font * 3)
    }
}

/// Başlık kutusu: proje ikonu, adı ve durumu; arka planı proje rengi (zemin durumu gösterir).
private struct TileLabel: View {
    let tile: OfficeSnapshot.Tile
    let icon: LoadedProjectIcon?
    let fontSize: Double

    var body: some View {
        HStack(spacing: fontSize * 0.4) {
            ProjectIconView(icon: icon, size: fontSize * 2.1)
            VStack(alignment: .leading, spacing: 1) {
                Text(tile.title)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(.white)
                if let status {
                    Text(status).font(.system(size: fontSize * 0.8, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(.leading, fontSize * 0.25)
        .padding(.trailing, 7)
        .padding(.vertical, fontSize * 0.25)
        .background(ProjectPalette.color(for: tile.placement.project).opacity(tile.state == .exited ? 0.5 : 0.92),
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.25), lineWidth: 0.5))
        .lineLimit(1)
        .fixedSize()
    }

    private var status: String? {
        switch tile.state {
        case .idle where tile.kind == .shell, .starting where tile.kind == .shell: "terminal"
        case .working(let tool?): tool
        case .idle: "z z"
        case .exited: "durdu"
        default: nil
        }
    }
}

/// Projenin ikonu (resim) ya da proje türünün sembolü, yuvarlatılmış kare içinde.
struct ProjectIconView: View {
    let icon: LoadedProjectIcon?
    let size: Double

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
    }
}

extension ProjectPalette {
    static func color(for project: String) -> Color {
        let c = colors[index(for: project)]
        return Color(red: c.red, green: c.green, blue: c.blue)
    }
}

/// Cevap bekleyen ajanın üstündeki turuncu, nabız gibi atan balon.
private struct QuestionBubble: View {
    let size: Double
    @State private var pulse = false

    var body: some View {
        Text("?")
            .font(.system(size: size * 0.6, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(.orange))
            .scaleEffect(pulse ? 1.12 : 0.92)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
