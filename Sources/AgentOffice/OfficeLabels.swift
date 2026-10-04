import AgentOfficeCore
import SwiftUI

/// Karoların başlıkları, tool adları ve `?` balonu: sahnenin üstüne SwiftUI ile çizilir, hiçbir zaman örtülmez.
struct OfficeLabels: View {
    let snapshot: OfficeSnapshot

    var body: some View {
        GeometryReader { geometry in
            let size = (width: Double(geometry.size.width), height: Double(geometry.size.height))
            let camera = OfficeScene.camera(for: snapshot.grid, aspect: size.width / max(size.height, 1))
            let fontSize = Self.fontSize(viewHeight: size.height, camera: camera)
            ForEach(snapshot.tiles, id: \.placement.id) { tile in
                let origin = OfficeScene.tileOrigin(tile.placement)
                let anchor = camera.project(origin + [0, IsoCamera.labelHeight, 0], viewSize: size)
                TileLabel(tile: tile, fontSize: fontSize)
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

    /// Tıklama için başlık kutusunun yaklaşık boyutu (iki satır: başlık ve durum).
    static func labelBox(viewHeight: Double, camera: IsoCamera) -> (width: Double, height: Double) {
        let font = fontSize(viewHeight: viewHeight, camera: camera)
        return (font * 7, font * 2.8)
    }
}

private struct TileLabel: View {
    let tile: OfficeSnapshot.Tile
    let fontSize: Double

    var body: some View {
        VStack(spacing: 1) {
            Text(tile.title)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(tile.state == .exited ? .secondary : .primary)
            switch tile.state {
            case .working(let tool?):
                Text(tool).font(.system(size: fontSize * 0.8, weight: .medium)).foregroundStyle(.cyan)
            case .idle:
                Text("z z").font(.system(size: fontSize * 0.8)).foregroundStyle(.secondary)
            case .exited:
                Text("durdu").font(.system(size: fontSize * 0.8)).foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
        .lineLimit(1)
        .fixedSize()
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
