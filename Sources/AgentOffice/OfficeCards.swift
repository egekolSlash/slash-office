import AgentOfficeCore
import SwiftUI

/// Sahnenin üstündeki SwiftUI katmanı (spec §5): oda tabelaları, masa kartları ve bekleyenlerin `?` balonu.
/// Konumlar sahneyle aynı `OfficeViewport` izdüşümünden gelir; tıklamalar sahneye geçer.
struct OfficeCards: View {
    let plan: OfficePlan
    let desks: [String: OfficeDeskInfo]
    let camera: OfficeCamera
    let icons: [String: LoadedProjectIcon]
    let interactive: Bool

    var body: some View {
        let viewport = camera.viewport
        let size = camera.viewSize
        let detail = interactive ? OfficeDetail.level(zoom: viewport.zoom) : .far
        ZStack(alignment: .topLeading) {
            ForEach(plan.rooms, id: \.key) { room in
                let anchor = viewport.project(x: room.doorX, y: OfficePlan.wallHeight + 0.25, z: room.doorZ, viewSize: size)
                RoomSign(title: room.title, roomKey: room.key, icon: icons[room.key], compact: detail == .far && !interactive)
                    .position(x: anchor.x, y: anchor.y)
            }
            ForEach(plan.rooms.flatMap(\.desks), id: \.id) { desk in
                if let info = desks[desk.id] {
                    let anchor = viewport.project(x: desk.x, y: 1.1, z: desk.z, viewSize: size)
                    if detail != .far {
                        DeskCard(info: info, near: detail == .near)
                            .position(x: anchor.x, y: anchor.y - 18)
                    }
                    if case .waiting = info.state {
                        QuestionBubble(size: max(18, min(viewport.zoom * 0.35, 34)))
                            .position(x: anchor.x, y: anchor.y - (detail == .far ? 6 : 52))
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }
}

private struct RoomSign: View {
    let title: String
    let roomKey: String
    let icon: LoadedProjectIcon?
    let compact: Bool

    var body: some View {
        HStack(spacing: 5) {
            ProjectIconView(icon: icon, size: compact ? 14 : 20)
            Text(title).font(.system(size: compact ? 10 : 12, weight: .semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(ProjectPalette.color(for: roomKey).opacity(0.92), in: RoundedRectangle(cornerRadius: 5))
        .fixedSize()
    }
}

private struct DeskCard: View {
    let info: OfficeDeskInfo
    let near: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if info.kind == .shell { Image(systemName: "apple.terminal").font(.system(size: 9)) }
                Text(info.worktree ?? info.title).font(.system(size: near ? 12 : 10, weight: .semibold))
            }
            StatusBadge(state: info.state, kind: info.kind).font(.system(size: near ? 10 : 9))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(info.focused ? 0.75 : 0.55), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(info.focused ? Color.white.opacity(0.8) : .clear, lineWidth: 1))
        .lineLimit(1)
        .fixedSize()
    }
}

/// Cevap bekleyen ajanın üstündeki turuncu balon. Sabit: SwiftUI'de sürekli animasyon boştaki ofiste ~%6 CPU
/// harcıyordu; titreşimi sahnedeki zemin ışığı (SpriteKit) yapar.
struct QuestionBubble: View {
    let size: Double

    var body: some View {
        Text("?")
            .font(.system(size: size * 0.6, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(.orange))
    }
}
