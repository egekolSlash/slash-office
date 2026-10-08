import AgentOfficeCore
import SwiftUI

/// "Görünümü düzenle…" (spec v3 §7): köylünün saçı, teni, tişörtü ve gözlüğü. Değişiklik ofiste anında görünür.
struct AvatarEditorSheet: View {
    @Bindable var model: AppModel
    let id: String

    private var look: AvatarLook { model.look(for: id) }
    private var projectColor: AvatarLook.RGBA {
        let key = model.store.session(id).map { model.roomKey(for: $0.cwd) } ?? id
        let c = ProjectPalette.colors[ProjectPalette.index(for: key)]
        return (c.red, c.green, c.blue)
    }

    private func update(_ change: (inout AvatarLook) -> Void) {
        var next = look
        change(&next)
        model.setLook(next, for: id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(model.store.session(id)?.title ?? "Köylü") · Görünüm").font(.title3.bold())
            Form {
                Picker("Saç", selection: Binding(get: { look.hairStyle }, set: { v in update { $0.hairStyle = v } })) {
                    Text("Kısa").tag(AvatarLook.HairStyle.short)
                    Text("At kuyruğu").tag(AvatarLook.HairStyle.pigtails)
                    Text("Dikenli").tag(AvatarLook.HairStyle.spiky)
                    Text("Küt").tag(AvatarLook.HairStyle.bob)
                }
                .pickerStyle(.segmented)
                LabeledContent("Saç rengi") {
                    Swatches(colors: AvatarLook.hairColors, selected: look.hairColor) { i in update { $0.hairColor = i } }
                }
                LabeledContent("Ten") {
                    Swatches(colors: AvatarLook.skinTones, selected: look.skin) { i in update { $0.skin = i } }
                }
                Picker("Tişört deseni", selection: Binding(get: { look.shirtPattern }, set: { v in update { $0.shirtPattern = v } })) {
                    Text("Düz").tag(AvatarLook.ShirtPattern.plain)
                    Text("Çizgili").tag(AvatarLook.ShirtPattern.stripes)
                    Text("Puantiyeli").tag(AvatarLook.ShirtPattern.dots)
                }
                .pickerStyle(.segmented)
                LabeledContent("Tişört rengi") {
                    HStack(spacing: 6) {
                        Swatch(color: projectColor, selected: look.shirtColor == nil, label: "Proje rengi") { update { $0.shirtColor = nil } }
                        Divider().frame(height: 18)
                        Swatches(colors: AvatarLook.shirtColors, selected: look.shirtColor ?? -1) { i in update { $0.shirtColor = i } }
                    }
                }
                Toggle("Gözlük", isOn: Binding(get: { look.glasses }, set: { v in update { $0.glasses = v } }))
            }
            .formStyle(.grouped)
            HStack {
                Button("Rastgele") {
                    var rng = SystemRandomNumberGenerator()
                    model.setLook(AvatarLook.random(using: &rng), for: id)
                }
                Button("Varsayılana dön") { model.setLook(nil, for: id) }
                Spacer()
                Button("Tamam") { model.editingAvatar = nil }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

/// "Odayı düzenle…": duvar kâğıdı, zemin ve halı (depo başına).
struct RoomEditorSheet: View {
    @Bindable var model: AppModel
    let roomKey: String

    static let wallpapers: [(name: String, color: AvatarLook.RGBA)] = [
        ("Krem çizgili", (0.98, 0.90, 0.76)), ("Nane çizgili", (0.81, 0.93, 0.86)), ("Pembe puantiyeli", (0.99, 0.86, 0.88)),
        ("Açık mavi", (0.84, 0.92, 0.99)), ("Sarı kareli", (0.99, 0.92, 0.68)),
    ]
    static let floors: [(name: String, color: AvatarLook.RGBA)] = [
        ("Meşe parke", (0.82, 0.58, 0.34)), ("Ceviz parke", (0.52, 0.33, 0.20)), ("Karo", (0.92, 0.74, 0.62)),
    ]

    private var style: RoomStyle { model.style(for: roomKey) }

    private func update(_ change: (inout RoomStyle) -> Void) {
        var next = style
        change(&next)
        model.setStyle(next, for: roomKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\((roomKey as NSString).lastPathComponent) · Oda").font(.title3.bold())
            Form {
                LabeledContent("Duvar kâğıdı") {
                    HStack(spacing: 6) {
                        ForEach(Array(Self.wallpapers.enumerated()), id: \.offset) { i, item in
                            Swatch(color: item.color, selected: style.wallpaper == i, label: item.name) { update { $0.wallpaper = i } }
                        }
                    }
                }
                LabeledContent("Zemin") {
                    HStack(spacing: 6) {
                        ForEach(Array(Self.floors.enumerated()), id: \.offset) { i, item in
                            Swatch(color: item.color, selected: style.floor == i, label: item.name) { update { $0.floor = i } }
                        }
                    }
                }
                Picker("Halı", selection: Binding(get: { style.rug }, set: { v in update { $0.rug = v } })) {
                    Text("Puantiyeli").tag(RoomStyle.RugPattern.dots)
                    Text("Çizgili").tag(RoomStyle.RugPattern.stripes)
                    Text("Düz").tag(RoomStyle.RugPattern.plain)
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            HStack {
                Button("Varsayılana dön") { model.setStyle(nil, for: roomKey) }
                Spacer()
                Button("Tamam") { model.editingRoom = nil }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

private struct Swatches: View {
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

private struct Swatch: View {
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
