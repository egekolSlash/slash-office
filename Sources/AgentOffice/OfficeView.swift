import AgentOfficeCore
import AppKit
import SwiftUI

/// Detaylı ofis (spec v3, v4): Animal Crossing tarzı gerçek zamanlı 3D ada, kendi Metal çizicimizle. `interactive`:
/// tam ekran ofis modunda gezinme açık; mini ofiste hep sığdırılmış, uzak görünüm ve en fazla 12 fps.
/// Varlıklar ya da Metal yoksa sade görünüm.
struct OfficeView: View {
    @Bindable var model: AppModel
    var interactive = false
    @State private var gpu: OfficeGPU?
    private var camera: OfficeCamera { interactive ? model.officeCamera : model.miniOfficeCamera }
    /// Mini ofisin kendiliğinden baktığı masa (`OfficeAutoFocus`).
    @State private var autoFocused: String?
    @State private var unavailable = false

    var body: some View {
        Group {
            if let gpu {
                content(gpu)
            } else if unavailable {
                SimpleOfficeView(model: model)
            } else {
                Color(red: 0.62, green: 0.82, blue: 1.0)
            }
        }
        .task {
            guard gpu == nil, !unavailable else { return }
            if let loaded = await OfficeGPU.shared() {
                gpu = loaded
            } else {
                unavailable = true
            }
        }
    }

    private func content(_ gpu: OfficeGPU) -> some View {
        let plan = model.officePlan()
        let desks = deskInfos(plan)
        let scene = OfficeSceneInput(
            plan: plan, desks: desks.mapValues { AvatarDeskState(state: $0.state, kind: $0.kind) },
            looks: Dictionary(uniqueKeysWithValues: desks.keys.map { ($0, model.look(for: $0)) }),
            styles: Dictionary(uniqueKeysWithValues: plan.rooms.map { ($0.key, model.style(for: $0.key)) }),
            terminals: Set(desks.values.filter { $0.kind == .shell }.map(\.id)),
            projectColors: Dictionary(uniqueKeysWithValues: plan.rooms.map { room in
                let c = ProjectPalette.colors[ProjectPalette.index(for: room.key)]
                return (room.key, (red: c.red, green: c.green, blue: c.blue))
            }))
        let camera = camera
        return OfficeMetalRepresentable(
            gpu: gpu, camera: camera, scene: scene, interactive: interactive,
            onClick: { x, y, clickCount, shift in handleClick(x: x, y: y, clickCount: clickCount, shift: shift, plan: plan, camera: camera) },
            onRightClick: { x, y in handleRightClick(x: x, y: y, plan: plan, camera: camera) },
            onPan: { dx, dy in camera.pan(dx: dx, dy: dy) },
            onZoom: { factor, x, y in camera.zoom(by: factor, anchorX: x, anchorY: y) },
            onResetKey: { camera.resetToFit() })
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            camera.viewSize = (Double(size.width), Double(size.height))
            camera.fit(plan)
        }
        .onChange(of: plan, initial: true) { camera.fit(plan) }
        .task(id: model.store.sessions.map(\.cwd)) { model.loadRoomKeys(model.store.sessions.map(\.cwd)) }
        // Oda anahtarları arka planda geldikçe (ör. sadece worktree açıkken ana depo) tabela ikonları yüklenir.
        .task(id: plan.rooms.map(\.key)) { model.loadProjectIcons(plan.rooms.map(\.key)) }
        .onChange(of: model.officeFocusRequest) {
            guard interactive, let id = model.officeFocusRequest else { return }
            model.officeFocusRequest = nil
            focusCamera(on: id, plan: plan, camera: camera)
        }
        .onChange(of: autoFocusTarget(plan: plan, desks: desks), initial: true) { _, target in
            applyAutoFocus(target, plan: plan, camera: camera)
        }
        // Elle hareketten sonraki bekleme bitince odak yeniden uygulansın.
        .task(id: interactive) {
            guard !interactive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                applyAutoFocus(autoFocusTarget(plan: model.officePlan(), desks: deskInfos(model.officePlan())),
                               plan: model.officePlan(), camera: camera)
            }
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

    /// Mini ofiste kameranın dönmesi gereken masa: soru soran > işi bitip görülmemiş > çalışan; panelde açık
    /// olmayan önce (ofis modunda kendiliğinden odak yok).
    private func autoFocusTarget(plan: OfficePlan, desks: [String: OfficeDeskInfo]) -> String? {
        guard !interactive else { return nil }
        let candidates = desks.values.map { info in
            OfficeAutoFocus.Candidate(id: info.id, state: info.state, unseenFinish: info.unseenFinish,
                                      openInPane: model.layout.visible.contains(info.id),
                                      lastEventAt: model.store.session(info.id)?.lastEventAt)
        }
        return OfficeAutoFocus.pick(candidates, current: autoFocused)
    }

    private func applyAutoFocus(_ target: String?, plan: OfficePlan, camera: OfficeCamera) {
        guard !interactive, !OfficeAutoFocus.isPaused(lastManualMove: camera.lastManualMove, now: Date()) else { return }
        guard target != autoFocused || (target != nil && camera.target == nil && !isLooking(at: target, plan: plan, camera: camera)) else { return }
        autoFocused = target
        guard let target, let desk = plan.rooms.flatMap(\.desks).first(where: { $0.id == target }) else {
            camera.resetToFit()
            return
        }
        camera.focus(x: desk.x, z: desk.z, zoom: max(camera.fitViewport.zoom * 2.2, 70))
    }

    /// Kamera zaten bu masaya bakıyor mu (yeniden odaklamaya gerek yok).
    private func isLooking(at id: String?, plan: OfficePlan, camera: OfficeCamera) -> Bool {
        guard let id, let desk = plan.rooms.flatMap(\.desks).first(where: { $0.id == id }) else { return false }
        return abs(camera.viewport.targetX - desk.x) < 0.3 && abs(camera.viewport.targetZ - desk.z) < 0.3
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
        let detail = OfficeDetail.level(zoom: camera.viewport.zoom)
        // Balonu olan masalar: bekleyenler (?) ve bitip görülmeyenler (✓).
        let waiting = Set(plan.rooms.flatMap(\.desks).map(\.id).filter { id in
            if case .waiting = model.store.session(id)?.state { return true }
            return model.store.session(id)?.unseenFinish == true
        })
        let standing = Set(plan.rooms.flatMap(\.desks).map(\.id).filter { id in
            if case .waiting = model.store.session(id)?.state { true } else { false }
        })
        return plan.desk(atViewX: x, y: y, viewport: camera.viewport, viewSize: camera.viewSize, detail: detail,
                         waiting: waiting, standing: standing)
    }

    private func handleClick(x: Double, y: Double, clickCount: Int, shift: Bool, plan: OfficePlan, camera: OfficeCamera) {
        if let id = deskID(atX: x, y: y, plan: plan, camera: camera) {
            DebugLog.write("office click (\(Int(x)),\(Int(y))) -> \(id)")
            if shift { model.addTerminal(id) } else { model.showTerminal(id) }
            return
        }
        let ground = camera.viewport.point(atX: x, y: y, height: 0, viewSize: camera.viewSize)
        // Boş arsaya tık: yeni Claude oturumu seçicisi (⌘N gibi).
        if plan.lot(atX: ground.x, z: ground.z) != nil {
            model.openLauncher(beside: false, claude: true)
            return
        }
        // Boş zemine çift tık: kamera o odaya yaklaşır.
        guard clickCount == 2 else { return }
        guard let room = plan.room(atX: ground.x, z: ground.z) else { return }
        let roomFit = OfficeViewport.fitting(room.rect, height: OfficePlan.wallHeight, viewSize: camera.viewSize, margin: 40)
        camera.focus(x: roomFit.targetX, z: roomFit.targetZ, zoom: roomFit.zoom)
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
        camera.focus(x: desk.x, z: desk.z, zoom: max(camera.viewport.zoom, 130))
    }
}
