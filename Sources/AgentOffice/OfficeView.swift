import AgentOfficeCore
import AppKit
import SwiftUI

/// Detaylı ofis (spec v3 §6): Animal Crossing tarzı gerçek zamanlı 3D ada. `interactive`: tam ekran ofis modunda
/// gezinme açık; mini ofiste hep sığdırılmış, uzak görünüm ve en fazla 12 fps. Varlıklar bulunamazsa sade görünüm.
struct OfficeView: View {
    @Bindable var model: AppModel
    var interactive = false
    @State private var scene: Office3DScene?
    @State private var unavailable = false

    var body: some View {
        Group {
            if let scene {
                content(scene)
            } else if unavailable {
                SimpleOfficeView(model: model)
            } else {
                Color(red: 0.62, green: 0.82, blue: 1.0)
            }
        }
        .task {
            guard scene == nil, !unavailable else { return }
            if let resources = await Office3DResources.shared(), let created = Office3DScene(resources: resources) {
                scene = created
            } else {
                unavailable = true
            }
        }
    }

    /// Sahneyi güncelleyen her şey: değişmediyse sahneye dokunulmaz.
    private struct SceneInput: Equatable {
        var plan: OfficePlan
        var desks: [String: OfficeDeskInfo]
        var looks: [String: AvatarLook]
        var styles: [String: RoomStyle]
    }

    private func content(_ scene: Office3DScene) -> some View {
        let plan = model.officePlan()
        let desks = deskInfos(plan)
        let input = SceneInput(plan: plan, desks: desks,
                               looks: Dictionary(uniqueKeysWithValues: desks.keys.map { ($0, model.look(for: $0)) }),
                               styles: Dictionary(uniqueKeysWithValues: plan.rooms.map { ($0.key, model.style(for: $0.key)) }))
        let camera = scene.camera
        return OfficeRenderRepresentable(
            scene: scene, interactive: interactive,
            onClick: { x, y, clickCount, shift in handleClick(x: x, y: y, clickCount: clickCount, shift: shift, plan: plan, camera: camera) },
            onRightClick: { x, y in handleRightClick(x: x, y: y, plan: plan, camera: camera) },
            onPan: { dx, dy in
                camera.target = nil
                camera.userMoved = true
                camera.viewport.pan(dx: dx, dy: dy)
            },
            onZoom: { factor, x, y in
                camera.target = nil
                camera.userMoved = true
                camera.viewport.zoom(by: factor, anchorX: x, anchorY: y, viewSize: camera.viewSize, limits: camera.limits)
            },
            onResetKey: { camera.resetToFit() })
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            camera.viewSize = (Double(size.width), Double(size.height))
            camera.fit(plan)
        }
        .onChange(of: input, initial: true) {
            camera.fit(input.plan)
            scene.update(plan: input.plan, desks: input.desks, look: { input.looks[$0] ?? AvatarLook.default(for: $0) },
                         style: { input.styles[$0] ?? RoomStyle.default(for: $0) })
        }
        .task(id: model.store.sessions.map(\.cwd)) { model.loadRoomKeys(model.store.sessions.map(\.cwd)) }
        // Oda anahtarları arka planda geldikçe (ör. sadece worktree açıkken ana depo) tabela ikonları yüklenir.
        .task(id: plan.rooms.map(\.key)) { model.loadProjectIcons(plan.rooms.map(\.key)) }
        .onChange(of: model.officeFocusRequest) {
            guard interactive, let id = model.officeFocusRequest else { return }
            model.officeFocusRequest = nil
            focusCamera(on: id, plan: plan, camera: camera)
        }
        .overlay {
            OfficeCards(plan: plan, desks: desks, camera: camera, icons: model.projectIcons, interactive: interactive)
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

    private func deskID(atX x: Double, y: Double, plan: OfficePlan, camera: OfficeCamera) -> String? {
        let detail = interactive ? OfficeDetail.level(zoom: camera.viewport.zoom) : .far
        // Balonu olan masalar: bekleyenler (?) ve bitip görülmeyenler (✓).
        let waiting = Set(plan.rooms.flatMap(\.desks).map(\.id).filter { id in
            if case .waiting = model.store.session(id)?.state { return true }
            return model.store.session(id)?.unseenFinish == true
        })
        return plan.desk(atViewX: x, y: y, viewport: camera.viewport, viewSize: camera.viewSize, detail: detail, waiting: waiting)
    }

    private func handleClick(x: Double, y: Double, clickCount: Int, shift: Bool, plan: OfficePlan, camera: OfficeCamera) {
        if let id = deskID(atX: x, y: y, plan: plan, camera: camera) {
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

    /// Sağ tık: masada "Görünümü düzenle…", odada "Odayı düzenle…".
    private func handleRightClick(x: Double, y: Double, plan: OfficePlan, camera: OfficeCamera) {
        if let id = deskID(atX: x, y: y, plan: plan, camera: camera) {
            model.editingAvatar = id
            return
        }
        let ground = camera.viewport.point(atX: x, y: y, height: 0, viewSize: camera.viewSize)
        if let room = plan.room(atX: ground.x, z: ground.z) { model.editingRoom = room.key }
    }

    /// ⌘J: kamera bekleyen masaya yaklaşır (yakın detay seviyesinde).
    private func focusCamera(on id: String, plan: OfficePlan, camera: OfficeCamera) {
        guard let desk = plan.rooms.flatMap(\.desks).first(where: { $0.id == id }) else { return }
        let point = OfficeViewport.screenPlane(x: desk.x, y: 0.5, z: desk.z)
        camera.userMoved = true
        camera.target = OfficeViewport(centerX: point.x, centerY: point.y, zoom: min(max(camera.viewport.zoom, 130), camera.limits.upperBound))
    }
}
