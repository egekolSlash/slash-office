import AgentOfficeCore
import SwiftUI
import UniformTypeIdentifiers

/// Terminal panelleri bölme ağacına göre (`TerminalLayout.root`): eklemeler 2 yan yana, 3–4 2×2 verir; sürükle-bırak
/// paneli bırakılan kenardan böler (spec §4).
struct TerminalGrid: View {
    @Bindable var model: AppModel
    let requestRemove: (String) -> Void

    var body: some View {
        if let root = model.layout.root {
            PaneNodeView(model: model, node: root, requestRemove: requestRemove)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("Terminal açık değil", systemImage: "terminal",
                                   description: Text("Ofisten bir ajana tıkla ya da ⌘T ile yeni panel aç."))
        }
    }
}

private struct PaneNodeView: View {
    @Bindable var model: AppModel
    let node: PaneNode
    let requestRemove: (String) -> Void

    var body: some View {
        switch node {
        case .leaf(let id):
            DroppablePane(model: model, id: id, requestRemove: requestRemove)
        case .split(.horizontal, let a, let b):
            HStack(spacing: 2) { child(a); child(b) }
        case .split(.vertical, let a, let b):
            VStack(spacing: 2) { child(a); child(b) }
        }
    }

    private func child(_ node: PaneNode) -> some View {
        PaneNodeView(model: model, node: node, requestRemove: requestRemove)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Bir panel ve üstüne sürüklenen oturum için bırakma bölgesi: kenarda o yarı, ortada bütün panel vurgulanır.
private struct DroppablePane: View {
    @Bindable var model: AppModel
    let id: String
    let requestRemove: (String) -> Void
    @State private var size: CGSize = .zero
    @State private var hover: PaneEdge?

    var body: some View {
        TerminalPane(model: model, id: id, requestRemove: requestRemove)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .overlay(alignment: alignment) {
                if let hover {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.22))
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: hover == .left || hover == .right ? size.width / 2 : nil,
                               height: hover == .top || hover == .bottom ? size.height / 2 : nil)
                        .padding(3)
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.12), value: hover)
                }
            }
            .onDrop(of: [.plainText], delegate: PaneDropDelegate(model: model, target: id, size: size, hover: $hover))
    }

    private var alignment: Alignment {
        switch hover {
        case .left: .leading
        case .right: .trailing
        case .top: .top
        case .bottom: .bottom
        default: .center
        }
    }
}

private struct PaneDropDelegate: DropDelegate {
    let model: AppModel
    let target: String
    let size: CGSize
    @Binding var hover: PaneEdge?

    func validateDrop(info: DropInfo) -> Bool {
        model.draggedPane != nil && info.hasItemsConforming(to: [.plainText])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let dragged = model.draggedPane else { return DropProposal(operation: .forbidden) }
        let edge = TerminalLayout.edge(x: info.location.x, y: info.location.y, width: size.width, height: size.height)
        let effective = model.layout.dropEdge(for: dragged, on: target, edge: edge)
        hover = dragged == target ? nil : effective
        return DropProposal(operation: dragged == target ? .cancel : .move)
    }

    func dropExited(info: DropInfo) { hover = nil }

    func performDrop(info: DropInfo) -> Bool {
        let edge = hover
        hover = nil
        guard let edge, let dragged = model.draggedPane,
              let provider = info.itemProviders(for: [.plainText]).first else { return false }
        let target = target
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? NSString, text as String == dragged else { return }
            Task { @MainActor in model.dropPane(dragged, on: target, edge: edge) }
        }
        return true
    }
}
