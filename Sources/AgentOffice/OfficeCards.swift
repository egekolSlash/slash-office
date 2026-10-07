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
        // Ekranın üst kenarına (ufka) yakın kalanlar gizlenir: bükülme bölgesinde okunmaz ve tıklaması şaşar.
        let horizon = size.height * 0.08
        ZStack(alignment: .topLeading) {
            ForEach(plan.rooms, id: \.key) { room in
                let anchor = viewport.project(x: room.doorX, y: OfficePlan.wallHeight + 0.25, z: room.doorZ, viewSize: size)
                if anchor.y > horizon {
                    RoomSign(title: room.title, roomKey: room.key, icon: icons[room.key], compact: detail == .far && !interactive)
                        .position(x: anchor.x, y: anchor.y)
                }
            }
            ForEach(Array(plan.lots.enumerated()), id: \.offset) { _, lot in
                let anchor = viewport.project(x: (lot.minX + lot.maxX) / 2, y: 0.95, z: lot.minZ + OfficePlan.lotSignZ, viewSize: size)
                if anchor.y > horizon { LotSign(compact: detail == .far && !interactive).position(x: anchor.x, y: anchor.y) }
            }
            ForEach(plan.rooms.flatMap(\.desks), id: \.id) { desk in
                if let info = desks[desk.id], OfficeOverlay.anchor(desk, viewport: viewport, viewSize: size).y > horizon {
                    let anchor = OfficeOverlay.anchor(desk, viewport: viewport, viewSize: size)
                    if detail != .far {
                        DeskCard(info: info, near: detail == .near)
                            .position(x: anchor.x, y: anchor.y - OfficeOverlay.cardOffset)
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
        Label("Yeni oda", systemImage: "plus")
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

private struct DeskCard: View {
    let info: OfficeDeskInfo
    let near: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if info.kind == .shell { Image(systemName: "apple.terminal").font(.system(size: 9)) }
                Text(info.worktree ?? info.title).font(.system(size: near ? 12 : 10, weight: .semibold))
            }
            // Yakın görünümde: ne üzerinde çalışıyor.
            if near, let summary = info.summary {
                Text(summary).font(.system(size: 10)).foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: 220, alignment: .leading)
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
