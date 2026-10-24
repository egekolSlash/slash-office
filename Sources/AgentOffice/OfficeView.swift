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
    static let autoFocusKey = "miniOfficeAutoFocus"
    /// Mini ofisin kendiliğinden baktığı yer (`OfficeAutoFocus`).
    @State private var autoFocused = OfficeAutoFocus.Target.overview
    @State private var unavailable = false
    /// Köylülerin yerleri: 0,2 sn'de bir okunur, sadece değişince güncellenir (dururken kartlar yeniden çizilmez).
    @State private var villagers: [String: AvatarSim.Position] = [:]
    /// Ayar değişince plan (masa yönü) yeniden kurulsun.
    @AppStorage(AppModel.deskOrientationKey) private var deskOrientation = DeskOrientation.horizontal

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
        _ = deskOrientation
        let plan = model.officePlan()
        let desks = deskInfos(plan)
        let scene = OfficeSceneInput(
            plan: plan, desks: desks.mapValues { AvatarDeskState(state: $0.state, kind: $0.kind, unseenFinish: $0.unseenFinish) },
            looks: Dictionary(uniqueKeysWithValues: desks.keys.map { ($0, model.look(for: $0)) }),
            styles: Dictionary(uniqueKeysWithValues: plan.rooms.map { ($0.key, model.style(for: $0.key)) }),
            terminals: Set(desks.values.filter { $0.kind == .shell }.map(\.id)),
            projectColors: Dictionary(uniqueKeysWithValues: plan.rooms.map { room in
                let c = ProjectPalette.colors[ProjectPalette.index(for: room.key)]
                return (room.key, (red: c.red, green: c.green, blue: c.blue))
            }),
            traits: desks.keys.reduce(into: [:]) { result, id in
                if let c = model.character(for: id) { result[id] = .init(personality: c.personality, signature: c.signature) }
            },
            jobs: desks.keys.reduce(into: [:]) { result, id in
                if let jobs = model.store.session(id)?.backgroundTasks, !jobs.isEmpty { result[id] = jobs.map(\.id) }
            })
        let camera = camera
        return OfficeMetalRepresentable(
            gpu: gpu, camera: camera, scene: scene, interactive: interactive,
            onClick: { x, y, clickCount, shift in handleClick(x: x, y: y, clickCount: clickCount, shift: shift, plan: plan, camera: camera) },
            onRightClick: { x, y in handleRightClick(x: x, y: y, plan: plan, camera: camera) },
            onPan: { dx, dy in camera.pan(dx: dx, dy: dy) },
            onZoom: { factor, x, y in camera.zoom(by: factor, anchorX: x, anchorY: y) },
            onResetKey: { camera.resetToFit() },
            onVillagers: { villagers = $0 })
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            camera.viewSize = (Double(size.width), Double(size.height))
            camera.fit(plan)
            // Mini ofis boyutu değişince odaktaki köylü (ya da odalar) yine ortada ve sığar.
            if !interactive, autoFocused != .overview, !OfficeAutoFocus.isPaused(lastManualMove: camera.lastManualMove, now: Date()) {
                frame(autoFocused, plan: plan, camera: camera)
            }
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
        // Hedef ya da duruşu (soru gelince köylü masanın yanına kalkar) değişince kamera yeniden ortalar.
        .onChange(of: autoFocusKey(plan: plan, desks: desks), initial: true) {
            applyAutoFocus(autoFocusTarget(plan: plan, desks: desks), plan: plan, camera: camera)
        }
        // Elle hareketten sonraki bekleme bitince odak bir kez yeniden uygulanır (sürekli yoklama yok).
        .task(id: camera.lastManualMove) {
            guard !interactive, camera.lastManualMove != nil else { return }
            try? await Task.sleep(for: .seconds(OfficeAutoFocus.manualPause + 0.1))
            guard !Task.isCancelled else { return }
            applyAutoFocus(autoFocusTarget(plan: model.officePlan(), desks: deskInfos(model.officePlan())),
                           plan: model.officePlan(), camera: camera)
        }
        .overlay {
            OfficeCards(plan: plan, desks: desks, camera: camera, icons: model.projectIcons, interactive: interactive,
                        villagers: villagers)
        }

        .overlay(alignment: .bottomLeading) {
            if !interactive, OfficeAutoFocus.isPaused(lastManualMove: camera.lastManualMove, now: Date()) {
                // Elle gezinince kendiliğinden odak bir süre bekler (sorular hariç).
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    if OfficeAutoFocus.isPaused(lastManualMove: camera.lastManualMove, now: context.date) {
                        Label("Auto focus paused", systemImage: "pause.circle")
                            .font(.caption2).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.5), in: Capsule())
                            .padding(6)
                    }
                }
            }
        }
        .overlay {
            if plan.rooms.isEmpty {
                ContentUnavailableView("The office is empty", systemImage: "building.2", description: Text("Press ⌘T to open a new pane."))
            }
        }
    }

    /// Mini ofiste kameranın dönmesi gereken masa: soru soran > işi bitip görülmemiş > çalışan; panelde açık
    /// olmayan önce (ofis modunda kendiliğinden odak yok).
    private func autoFocusCandidates(_ desks: [String: OfficeDeskInfo]) -> [OfficeAutoFocus.Candidate] {
        desks.values.map { info in
            OfficeAutoFocus.Candidate(id: info.id, state: info.state, unseenFinish: info.unseenFinish,
                                      openInPane: model.layout.visible.contains(info.id),
                                      since: model.store.session(info.id)?.attentionSince)
        }
    }

    /// Dikkat isteyen masa; yoksa odaktaki panelin köylüsü; o da yoksa işin döndüğü odalar.
    private func autoFocusTarget(plan: OfficePlan, desks: [String: OfficeDeskInfo]) -> OfficeAutoFocus.Target {
        guard !interactive else { return .overview }
        let focusedPane = model.layout.focused.flatMap { desks[$0] == nil ? nil : $0 }
        return OfficeAutoFocus.target(autoFocusCandidates(desks), current: autoFocused, focusedPane: focusedPane,
                                      activeRooms: activeRooms(desks))
    }

    /// Panelde açık oturumların odaları (sıralı: anahtar her çizimde aynı kalsın) ve en son hareket olan oturumun odası.
    private func activeRooms(_ desks: [String: OfficeDeskInfo]) -> [String] {
        let open = Set(model.layout.visible.compactMap { desks[$0]?.roomKey }).sorted()
        let latest = desks.values.compactMap { info -> (String, Date)? in
            guard let session = model.store.session(info.id), let at = session.lastEventAt else { return nil }
            if case .exited = session.state { return nil }
            return (info.roomKey, at)
        }.max { $0.1 < $1.1 }?.0
        return OfficeAutoFocus.activeRooms(openRooms: open, latestRoom: latest)
    }

    private func autoFocusKey(plan: OfficePlan, desks: [String: OfficeDeskInfo]) -> String {
        switch autoFocusTarget(plan: plan, desks: desks) {
        case .villager(let id):
            let standing = if case .waiting = desks[id]?.state { true } else { false }
            return "\(id)|\(standing)"
        case .rooms(let keys): return "rooms|" + keys.joined(separator: ",")
        case .overview: return ""
        }
    }

    private func applyAutoFocus(_ target: OfficeAutoFocus.Target, plan: OfficePlan, camera: OfficeCamera) {
        guard !interactive, UserDefaults.standard.object(forKey: Self.autoFocusKey) as? Bool ?? true else { return }
        let candidates = autoFocusCandidates(deskInfos(plan))
        let lookingElsewhere = target.villager != nil && camera.target == nil
            && !isLooking(at: target.villager, plan: plan, camera: camera)
        let apply = OfficeAutoFocus.shouldApply(target: target, current: autoFocused, candidates: candidates,
                                                lastManualMove: camera.lastManualMove, now: Date())
            || (lookingElsewhere && !OfficeAutoFocus.isPaused(lastManualMove: camera.lastManualMove, now: Date()))
        guard apply else {
            if target != autoFocused { DebugLog.write("office autofocus waits (manual move) for \(target)") }
            return
        }
        DebugLog.write("office autofocus \(autoFocused) -> \(target)")
        autoFocused = target
        frame(target, plan: plan, camera: camera)
    }

    /// Kamerayı hedefe çevirir: köylüye yaklaşır, odaları sığdırır ya da bütün ofise döner.
    private func frame(_ target: OfficeAutoFocus.Target, plan: OfficePlan, camera: OfficeCamera) {
        switch target {
        case .villager(let id) where plan.rooms.flatMap(\.desks).contains(where: { $0.id == id }):
            focusVillager(id, plan: plan, camera: camera,
                          zoom: OfficeViewport.focusZoom(viewSize: camera.viewSize, fit: camera.fitViewport))
        case .rooms(let keys):
            let rects = plan.rooms.filter { keys.contains($0.key) }.map(\.rect)
            // Bütün odalar işteyse bütün ofis zaten sığdırılmış görünümdür.
            guard let first = rects.first, rects.count < plan.rooms.count else { camera.resetToFit(); return }
            let union = rects.dropFirst().reduce(first) { a, b in
                PlanRect(minX: min(a.minX, b.minX), minZ: min(a.minZ, b.minZ), maxX: max(a.maxX, b.maxX), maxZ: max(a.maxZ, b.maxZ))
            }
            let fit = OfficeViewport.fitting(union, height: OfficePlan.wallHeight, viewSize: camera.viewSize, margin: 40)
            // Tek küçük oda köylü odağından daha yakına gelmesin.
            let zoom = min(fit.zoom, OfficeViewport.focusZoom(viewSize: camera.viewSize, fit: camera.fitViewport))
            camera.focus(x: fit.targetX, z: fit.targetZ, zoom: zoom)
        default:
            camera.resetToFit()
        }
    }

    /// Köylünün gövdesini ortalar: oturuyorsa taburede, soru bekliyorsa masanın yanında ayakta.
    private func focusVillager(_ id: String, plan: OfficePlan, camera: OfficeCamera, zoom: Double) {
        guard let desk = plan.rooms.flatMap(\.desks).first(where: { $0.id == id }) else { return }
        let standing = if case .waiting = model.store.session(id)?.state { true } else { false }
        let body = plan.villagerFocus(desk, standing: standing)
        camera.follow(id, zoom: zoom, fallback: body)
    }

    /// Kamera zaten bu köylüye bakıyor mu (yeniden odaklamaya gerek yok): gövdesi ekranın ortasına yakın.
    private func isLooking(at id: String?, plan: OfficePlan, camera: OfficeCamera) -> Bool {
        if let id, camera.follow == id { return true }
        guard let id, let desk = plan.rooms.flatMap(\.desks).first(where: { $0.id == id }) else { return false }
        let standing = if case .waiting = model.store.session(id)?.state { true } else { false }
        let body = plan.villagerFocus(desk, standing: standing)
        let p = camera.viewport.project(x: body.x, y: body.y, z: body.z, viewSize: camera.viewSize)
        return abs(p.x - camera.viewSize.width / 2) < 12 && abs(p.y - camera.viewSize.height / 2) < 12
    }

    private func deskInfos(_ plan: OfficePlan) -> [String: OfficeDeskInfo] {
        var result: [String: OfficeDeskInfo] = [:]
        for room in plan.rooms {
            for desk in room.desks {
                guard let session = model.store.session(desk.id) else { continue }
                result[desk.id] = OfficeDeskInfo(
                    id: desk.id, title: session.title, state: session.state, kind: model.kind(of: desk.id),
                    roomKey: room.key, worktree: model.worktree(for: session.cwd),
                    focused: model.layout.focused == desk.id, summary: session.workSummary, unseenFinish: session.unseenFinish,
                    name: model.overheadLabel(for: desk.id))
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
        let focused = model.layout.focused.map { [$0] } ?? []
        return plan.desk(atViewX: x, y: y, viewport: camera.viewport, viewSize: camera.viewSize, detail: detail,
                         waiting: waiting, standing: standing, focused: focused, villagers: villagers)
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
        focusVillager(id, plan: plan, camera: camera, zoom: max(camera.viewport.zoom, 130))
    }
}
