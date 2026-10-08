import AgentOfficeCore
import SwiftUI

/// "Odayı düzenle…": duvar kâğıdı, zemin ve halı (depo başına).
struct RoomEditorSheet: View {
    @Bindable var model: AppModel
    let roomKey: String

    static let wallpapers: [(name: String, color: AvatarLook.RGBA)] = [
        (String(localized: "Cream stripes"), (0.98, 0.90, 0.76)), (String(localized: "Mint stripes"), (0.81, 0.93, 0.86)),
        (String(localized: "Pink polka dots"), (0.99, 0.86, 0.88)), (String(localized: "Light blue"), (0.84, 0.92, 0.99)),
        (String(localized: "Yellow checks"), (0.99, 0.92, 0.68)),
    ]
    static let floors: [(name: String, color: AvatarLook.RGBA)] = [
        (String(localized: "Oak parquet"), (0.82, 0.58, 0.34)), (String(localized: "Walnut parquet"), (0.52, 0.33, 0.20)),
        (String(localized: "Tile"), (0.92, 0.74, 0.62)),
    ]

    static func furnitureName(_ item: RoomFurniture) -> LocalizedStringKey {
        switch item {
        case .sofa: "Sofa"
        case .coffeeTable: "Coffee table"
        case .waterCooler: "Water cooler"
        case .plant: "Plant"
        case .bookshelf: "Bookshelf"
        case .arcade: "Arcade"
        case .whiteboard: "Whiteboard"
        case .coffeeMachine: "Coffee machine"
        }
    }

    private var style: RoomStyle { model.style(for: roomKey) }

    private func update(_ change: (inout RoomStyle) -> Void) {
        var next = style
        change(&next)
        model.setStyle(next, for: roomKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\((roomKey as NSString).lastPathComponent) · Room").font(.title3.bold())
            Form {
                LabeledContent("Wallpaper") {
                    HStack(spacing: 6) {
                        ForEach(Array(Self.wallpapers.enumerated()), id: \.offset) { i, item in
                            Swatch(color: item.color, selected: style.wallpaper == i, label: item.name) { update { $0.wallpaper = i } }
                        }
                    }
                }
                LabeledContent("Floor") {
                    HStack(spacing: 6) {
                        ForEach(Array(Self.floors.enumerated()), id: \.offset) { i, item in
                            Swatch(color: item.color, selected: style.floor == i, label: item.name) { update { $0.floor = i } }
                        }
                    }
                }
                Picker("Rug", selection: Binding(get: { style.rug }, set: { v in update { $0.rug = v } })) {
                    Text("Polka dots").tag(RoomStyle.RugPattern.dots)
                    Text("Striped").tag(RoomStyle.RugPattern.stripes)
                    Text("Plain").tag(RoomStyle.RugPattern.plain)
                }
                .pickerStyle(.segmented)
                Section("Furniture") {
                    // Kapalı eşya çizilmez; köylüler oraya gitmez.
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]) {
                        ForEach(RoomFurniture.allCases, id: \.self) { item in
                            Toggle(Self.furnitureName(item), isOn: Binding(
                                get: { style.furniture.contains(item) },
                                set: { on in update { if on { $0.furniture.insert(item) } else { $0.furniture.remove(item) } } }))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Reset to Default") { model.setStyle(nil, for: roomKey) }
                Spacer()
                Button("Done") { model.editingRoom = nil }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

struct Swatches: View {
    let colors: [AvatarLook.RGBA]
    let selected: Int
    let pick: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(colors.enumerated()), id: \.offset) { i, c in
                Swatch(color: c, selected: selected == i, label: nil) { pick(i) }
            }
        }
    }
}

struct Swatch: View {
    let color: AvatarLook.RGBA
    let selected: Bool
    let label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(red: color.red, green: color.green, blue: color.blue))
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(selected ? Color.accentColor : Color.black.opacity(0.2), lineWidth: selected ? 3 : 1))
        }
        .buttonStyle(.plain)
        .help(label ?? "")
    }
}
