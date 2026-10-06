import AgentOfficeCore
import AppKit
import SpriteKit
import SwiftUI

/// Ofis (spec §5). `interactive`: tam ekran ofis modunda gezinme açık; mini ofiste hep sığdırılmış ve uzak görünüm.
struct OfficeView: View {
    @Bindable var model: AppModel
    var interactive = false
    @State private var scene = OfficeSpriteScene(size: CGSize(width: 800, height: 500))

    var body: some View {
        let plan = model.officePlan()
        let desks = deskInfos(plan)
        OfficeSpriteView(scene: scene, interactive: interactive,
                         onClick: { x, y, clickCount, shift in
                             handleClick(x: x, y: y, clickCount: clickCount, shift: shift, plan: plan)
                         },
                         onPan: { dx, dy in
                             let camera = scene.officeCamera
                             camera.target = nil
                             camera.userMoved = true
                             camera.viewport.pan(dx: dx, dy: dy)
                         },
                         onZoom: { factor, x, y in
                             let camera = scene.officeCamera
                             camera.target = nil
                             camera.userMoved = true
                             camera.viewport.zoom(by: factor, anchorX: x, anchorY: y, viewSize: camera.viewSize, limits: camera.limits)
                         },
                         onResetKey: { scene.officeCamera.resetToFit() })
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            scene.officeCamera.viewSize = (Double(size.width), Double(size.height))
            scene.officeCamera.fit(plan)
        }
        .onChange(of: plan, initial: true) {
            scene.officeCamera.fit(plan)
            scene.render(plan: plan, desks: desks)
        }
        .onChange(of: desks) { scene.render(plan: plan, desks: desks) }
        .task(id: model.store.sessions.map(\.cwd)) { model.loadRoomKeys(model.store.sessions.map(\.cwd)) }
        // Oda anahtarları arka planda geldikçe (ör. sadece worktree açıkken ana depo) tabela ikonları yüklenir.
        .task(id: plan.rooms.map(\.key)) { model.loadProjectIcons(plan.rooms.map(\.key)) }
        .onChange(of: model.officeFocusRequest) {
            guard interactive, let id = model.officeFocusRequest else { return }
            model.officeFocusRequest = nil
            focusCamera(on: id, plan: plan)
        }
        .overlay {
            OfficeCards(plan: plan, desks: desks, camera: scene.officeCamera, icons: model.projectIcons, interactive: interactive)
        }
        .overlay {
            if plan.rooms.isEmpty {
                ContentUnavailableView("Ofis boş", systemImage: "building.2", description: Text("⌘T ile yeni panel aç."))
            }
        }
    }

    private func deskInfos(_ plan: OfficePlan) -> [String: OfficeDeskInfo] {
        var result: [String: OfficeDeskInfo] = [:]
        for room in plan.rooms {
            for desk in room.desks {
                guard let session = model.store.session(desk.id) else { continue }
                result[desk.id] = OfficeDeskInfo(
                    id: desk.id, title: session.title, state: session.state, kind: model.kind(of: desk.id),
                    roomKey: room.key, worktree: model.worktree(for: session.cwd),
                    focused: model.layout.focused == desk.id, summary: session.workSummary, unseenFinish: session.unseenFinish)
            }
        }
        return result
    }

    private func handleClick(x: Double, y: Double, clickCount: Int, shift: Bool, plan: OfficePlan) {
        let camera = scene.officeCamera
        let detail = interactive ? OfficeDetail.level(zoom: camera.viewport.zoom) : .far
        // Balonu olan masalar: bekleyenler (?) ve bitip görülmeyenler (✓).
        let waiting = Set(plan.rooms.flatMap(\.desks).map(\.id).filter { id in
            if case .waiting = model.store.session(id)?.state { return true }
            return model.store.session(id)?.unseenFinish == true
        })
        if let id = plan.desk(atViewX: x, y: y, viewport: camera.viewport, viewSize: camera.viewSize,
                              detail: detail, waiting: waiting) {
            DebugLog.write("office click (\(Int(x)),\(Int(y))) -> \(id)")
            if shift { model.addTerminal(id) } else { model.showTerminal(id) }
            return
        }
        // Boş zemine çift tık: kamera o odaya yaklaşır (sadece ofis modunda).
        guard interactive, clickCount == 2 else { return }
        let ground = camera.viewport.point(atX: x, y: y, height: 0, viewSize: camera.viewSize)
        guard let room = plan.room(atX: ground.x, z: ground.z) else { return }
        camera.userMoved = true
        var target = OfficeViewport.fitting(room.rect, height: OfficePlan.wallHeight, viewSize: camera.viewSize, margin: 40)
        target.zoom = min(max(target.zoom, camera.limits.lowerBound), camera.limits.upperBound)
        camera.target = target
    }

    /// ⌘J: kamera bekleyen masaya yaklaşır (yakın detay seviyesinde).
    private func focusCamera(on id: String, plan: OfficePlan) {
        guard let desk = plan.rooms.flatMap(\.desks).first(where: { $0.id == id }) else { return }
        let camera = scene.officeCamera
        let point = OfficeViewport.screenPlane(x: desk.x, y: 0.5, z: desk.z)
        camera.userMoved = true
        camera.target = OfficeViewport(centerX: point.x, centerY: point.y, zoom: min(max(camera.viewport.zoom, 130), camera.limits.upperBound))
    }
}
