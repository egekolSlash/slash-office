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
    /// Köylülerin o anki yerleri: kart ve balon köylüyü izler (boştaki köylü masada değil).
    var villagers: [String: AvatarSim.Position] = [:]

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
            // Bilgi kartı yok (yer kaplıyor, yerleşimi kayınca titriyordu): yalnız karakterin adı (· rolü) başın hemen
            // üstünde; bekleyen / bitip görülmeyen köylüde balon onun üstünde.
            let standing = Set(desks.values.filter { if case .waiting = $0.state { true } else { false } }.map(\.id))
            let tagHeight = detail == .near ? 18.0 : 15.0
            ForEach(visibleDesks, id: \.id) { desk in
                if let info = desks[desk.id] {
                    let anchor = plan.headAnchor(desk, standing: standing.contains(desk.id), viewport: viewport, viewSize: size,
                                                 villagers: villagers)
                    let lift = info.name == nil || detail == .far ? 0 : tagHeight
                    if let name = info.name, detail != .far {
                        NameTag(name: name, focused: info.focused, near: detail == .near)
                            .position(x: anchor.x, y: anchor.y - tagHeight / 2 - 2)
                    }
                    if case .waiting = info.state {
                        QuestionBubble(size: OfficeOverlay.bubbleSize(zoom: viewport.zoom))
                            .position(x: anchor.x, y: anchor.y - OfficeOverlay.bubbleOffset(detail) - lift)
                    } else if info.unseenFinish {
                        FinishedBubble(size: OfficeOverlay.bubbleSize(zoom: viewport.zoom))
                            .position(x: anchor.x, y: anchor.y - OfficeOverlay.bubbleOffset(detail) - lift)
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

/// Köylünün adı (· rolü): küçük, başın üstünde ortalı.
private struct NameTag: View {
    let name: String
    let focused: Bool
    let near: Bool

    var body: some View {
        Text(verbatim: name)
            .font(.system(size: near ? 11 : 9, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(.black.opacity(focused ? 0.7 : 0.45), in: Capsule())
            .fixedSize()
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
