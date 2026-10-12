import AgentOfficeCore
import SwiftUI

/// Odanın stili (özelleştirme penceresinin oda sayfasında): duvar kâğıdı, zemin, halı, eşyalar ve dekor.
struct RoomStyleSections: View {
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

    static func decorName(_ item: RoomDecor) -> LocalizedStringKey {
        switch item {
        case .printer: "Printer"
        case .fileCabinet: "File cabinet"
        case .serverRack: "Server rack"
        case .miniFridge: "Mini fridge"
        case .vendingMachine: "Vending machine"
        case .beanbag: "Beanbag"
        case .floorLamp: "Floor lamp"
        case .bigPlant: "Big plant"
        case .cactus: "Cactus"
        case .trashBin: "Trash bin"
        case .wallClock: "Wall clock"
        case .corkboard: "Corkboard"
        case .picture: "Picture"
        }
    }

    static func slotName(_ id: String) -> LocalizedStringKey {
        switch id {
        case "side": "By the window"
        case "lounge": "Lounge corner"
        case "sofaWall": "Above the sofa"
        default: "Back wall"
        }
    }

    private var style: RoomStyle { model.style(for: roomKey) }

    /// Seçili eşya (kayıt yoksa odanın varsayılanı); boş: nil.
    private func decorBinding(_ slot: DecorSlot) -> Binding<RoomDecor?> {
        Binding(get: { style.decor[slot.id] ?? OfficePlan.Room.defaultDecor(slot: slot, roomKey: roomKey) },
                set: { value in update { $0.decor[slot.id] = .some(value) } })
    }

    private func update(_ change: (inout RoomStyle) -> Void) {
        var next = style
        change(&next)
        model.setStyle(next, for: roomKey)
    }

    /// Odanın dekor yuvaları: ofiste açıksa oradaki oda, değilse tek odalı örnek plan.
    private var decorSlots: [DecorSlot] {
        if let room = model.officePlan().rooms.first(where: { $0.key == roomKey }) { return room.decorSlots }
        let member = OfficePlan.Member(id: "preview", roomKey: roomKey)
        return OfficePlan.make([member], slots: OfficePlan.assignSlots([member], previous: [:])).rooms.first?.decorSlots ?? []
    }

    var body: some View {
        Section("Style") {
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
        }
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
        Section("Decor") {
            ForEach(decorSlots, id: \.id) { slot in
                Picker(Self.slotName(slot.id), selection: decorBinding(slot)) {
                    Text("Empty").tag(RoomDecor?.none)
                    ForEach(RoomDecor.allCases.filter(slot.accepts), id: \.self) { item in
                        Text(Self.decorName(item)).tag(RoomDecor?.some(item))
                    }
                }
            }
        }
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
