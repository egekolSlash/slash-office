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
        let detail = OfficeDetail.level(zoom: viewport.zoom)
        // Ufkun arkasındakiler ve ekranın üst bandındakiler gizlenir (tıklama testiyle aynı kural, Core).
        let horizon = viewport.horizonZ(viewSize: size)
        let shown = { (z: Double, y: Double) in OfficeOverlay.isShown(z: z, anchorY: y, horizonZ: horizon, viewSize: size) }
        ZStack(alignment: .topLeading) {
            ForEach(plan.rooms, id: \.key) { room in
                let anchor = OfficeOverlay.roomSignAnchor(room, viewport: viewport, viewSize: size)
                if shown(room.z, anchor.y) {
                    RoomSign(title: room.title, roomKey: room.key, icon: icons[room.key], compact: detail == .far && !interactive)
                        .position(x: anchor.x, y: anchor.y)
                }
            }
            ForEach(Array(plan.lots.enumerated()), id: \.offset) { _, lot in
                let anchor = viewport.project(x: (lot.minX + lot.maxX) / 2, y: 0.95, z: lot.minZ + OfficePlan.lotSignZ, viewSize: size)
                if shown(lot.minZ + OfficePlan.lotSignZ, anchor.y) { LotSign(compact: detail == .far && !interactive).position(x: anchor.x, y: anchor.y) }
            }
            let visibleDesks = plan.rooms.flatMap(\.desks).filter { desk in
                desks[desk.id] != nil && shown(desk.z, OfficeOverlay.anchor(desk, viewport: viewport, viewSize: size).y)
            }
            // Kartlar başın yanında, birbirinin üstüne binmeden (Core: tıklama testiyle aynı yerleşim).
            let standing = Set(desks.values.filter { if case .waiting = $0.state { true } else { false } }.map(\.id))
            let bubbles = Set(desks.values.filter { info in
                if case .waiting = info.state { return true }
                return info.unseenFinish
            }.map(\.id))
            let focused = desks.values.filter(\.focused).map(\.id)
            let frames = plan.cardFrames(visibleDesks, standing: standing, bubbles: bubbles, focused: focused,
                                         viewport: viewport, viewSize: size, detail: detail)
            let cardSize = OfficeOverlay.cardSize(detail)
            ForEach(visibleDesks, id: \.id) { desk in
                if let info = desks[desk.id] {
                    let anchor = plan.headAnchor(desk, standing: standing.contains(desk.id), viewport: viewport, viewSize: size)
                    if let frame = frames[desk.id] {
                        DeskCard(info: info, near: detail == .near, size: cardSize)
                            .scaleEffect(frame.scale)
                            .position(x: frame.x, y: frame.y)
                    }
                    if case .waiting = info.state {
                        QuestionBubble(size: OfficeOverlay.bubbleSize(zoom: viewport.zoom))
                            .position(x: anchor.x, y: anchor.y - OfficeOverlay.bubbleOffset(detail))
                    } else if info.unseenFinish {
                        FinishedBubble(size: OfficeOverlay.bubbleSize(zoom: viewport.zoom))
                            .position(x: anchor.x, y: anchor.y - OfficeOverlay.bubbleOffset(detail))
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }
}

/// Boş arsanın tabelası: tıklanınca yeni oturum açılır (tıklama sahnede, `OfficeView`).
private struct LotSign: View {
    let compact: Bool

    var body: some View {
        Label("New Room", systemImage: "plus")
            .font(.system(size: compact ? 10 : 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(red: 0.55, green: 0.40, blue: 0.25).opacity(0.9), in: RoundedRectangle(cornerRadius: 5))
            .fixedSize()
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

/// Masa kartı: köylünün başının yanında, sabit boyutta (yerleşim ve tıklama testi bu boyutu varsayar; uzun yazılar kısalır).
private struct DeskCard: View {
    let info: OfficeDeskInfo
    let near: Bool
    let size: (width: Double, height: Double)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if info.kind == .shell { Image(systemName: "apple.terminal").font(.system(size: 9)) }
                Text(info.worktree ?? info.title).font(.system(size: near ? 12 : 10, weight: .semibold))
            }
            // Yakın görünümde: ne üzerinde çalışıyor.
            if near, let summary = info.summary {
                Text(summary).font(.system(size: 10)).foregroundStyle(.white.opacity(0.85))
            }
            StatusBadge(state: info.state, kind: info.kind).font(.system(size: near ? 10 : 9))
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(width: size.width, height: size.height, alignment: .leading)
        .background(.black.opacity(info.focused ? 0.75 : 0.55), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(info.focused ? Color.white.opacity(0.8) : .clear, lineWidth: 1))
    }
}

/// Cevap bekleyen ajanın üstündeki turuncu balon. Sabit: SwiftUI'de sürekli animasyon boştaki ofiste ~%6 CPU
/// harcıyordu; titreşimi sahnedeki zemin ışığı (SpriteKit) yapar.
struct QuestionBubble: View {
    let size: Double

    var body: some View {
        Text(verbatim: "?")
            .font(.system(size: size * 0.6, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(.orange))
    }
}
