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
        OfficeSpriteView(scene: scene) { x, y, clickCount, shift in
            handleClick(x: x, y: y, clickCount: clickCount, shift: shift, plan: plan)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            scene.officeCamera.viewSize = (Double(size.width), Double(size.height))
            scene.officeCamera.fit(plan)
        }
        .onChange(of: plan, initial: true) {
            scene.officeCamera.fit(plan)
            scene.render(plan: plan, desks: desks)
        }
        .onChange(of: desks) { scene.render(plan: plan, desks: desks) }
        .task(id: model.store.sessions.map(\.cwd)) {
            let cwds = model.store.sessions.map(\.cwd)
            model.loadRoomKeys(cwds)
            model.loadProjectIcons(cwds + plan.rooms.map(\.key))
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
                    roomKey: room.key, worktree: RepoIdentity.worktreeName(directory: session.cwd, roomKey: room.key),
                    focused: model.layout.focused == desk.id)
            }
        }
        return result
    }

    private func handleClick(x: Double, y: Double, clickCount: Int, shift: Bool, plan: OfficePlan) {
        let camera = scene.officeCamera
        guard let id = plan.desk(atViewX: x, y: y, viewport: camera.viewport, viewSize: camera.viewSize) else { return }
        DebugLog.write("office click (\(Int(x)),\(Int(y))) -> \(id)")
        if shift { model.addTerminal(id) } else { model.showTerminal(id) }
    }
}
