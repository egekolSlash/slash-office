import AgentOfficeCore
import AppKit
import SwiftUI

/// Karakterler ve odalar (⇧⌘A): solda oturumlar, kalıcı karakterler, odalar ve paketler; ortada seçilenin ayarları,
/// sağda köylü canlı. Değişiklik anında kaydedilir ve ofise yansır. Pencerede ve rehberde (`compact`) kullanılır.
struct AgentCustomizer: View {
    @Bindable var model: AppModel
    var compact = false
    @State private var selection: Pick?

    enum Pick: Hashable {
        case session(String), character(String), room(String), packs
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: compact ? 190 : 240)
            Divider()
            detail
        }
        .onAppear {
            selection = model.customizingRoom.map(Pick.room) ?? model.customizingAgent.map(Pick.session) ?? selection
                ?? model.store.sessions.first.map { .session($0.id) } ?? model.characters.first.map { .character($0.id) }
        }
        .task { if model.wardrobe.tops.isEmpty { await model.reloadPacks() } }
        // "Edit Appearance…" / "Edit Room…" seçimi getirir.
        .onChange(of: model.customizingAgent) { if let id = model.customizingAgent { selection = .session(id) } }
        .onChange(of: model.customizingRoom) { if let key = model.customizingRoom { selection = .room(key) } }
        .onChange(of: selection) {
            if case .session(let id) = selection { model.customizingAgent = id }
            if case .room(let key) = selection { model.customizingRoom = key } else { model.customizingRoom = nil }
        }
    }

    /// Kayıtlı odalar ve oturumu olan odalar.
    private var roomKeys: [String] {
        let live = model.store.sessions.map { model.roomKey(for: $0.cwd) }
        return Array(Set(model.rooms.keys).union(live)).sorted { model.roomName(for: $0).localizedStandardCompare(model.roomName(for: $1)) == .orderedAscending }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            if !model.store.sessions.isEmpty {
                Section("Sessions") {
                    ForEach(model.store.sessions) { session in
                        HStack(spacing: 8) {
                            ProjectIconView(icon: model.projectIcons[session.cwd], size: 20, isShell: model.kind(of: session.id) == .shell)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: model.displayName(for: session.id)).lineLimit(1)
                                Text(verbatim: model.character(for: session.id) == nil ? String(localized: "Random look") : session.title)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .tag(Pick.session(session.id))
                    }
                }
            }
            Section {
                ForEach(model.characters) { character in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: character.name).lineLimit(1)
                        if let role = character.role { Text(verbatim: role).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    .tag(Pick.character(character.id))
                    .contextMenu {
                        Button("Duplicate") { if let id = model.duplicateCharacter(character.id) { selection = .character(id) } }
                        Button("Delete", role: .destructive) { model.deleteCharacter(character.id) }
                    }
                }
                .onMove { model.moveCharacters(from: $0, to: $1) }
            } header: {
                HStack {
                    Text("Characters")
                    Spacer()
                    Button { selection = .character(model.addCharacter()) } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless).help(Text("New Character"))
                }
            }
            Section {
                ForEach(roomKeys, id: \.self) { key in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: model.roomName(for: key)).lineLimit(1)
                        Text("\(model.room(for: key).cast.count) characters").font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(Pick.room(key))
                }
            } header: {
                HStack {
                    Text("Rooms")
                    Spacer()
                    Button { addRoom() } label: { Image(systemName: "plus") }.buttonStyle(.borderless).help(Text("New Room…"))
                }
            }
            if !compact {
                Section("Downloads") {
                    Label("Packs", systemImage: "shippingbox").tag(Pick.packs)
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .session(let id) where model.store.session(id) != nil:
            SessionDetail(model: model, id: id, compact: compact)
        case .character(let id) where model.character(id: id) != nil:
            CharacterDetail(model: model, id: id, compact: compact) { selection = nil }
        case .room(let key):
            RoomDetail(model: model, roomKey: key) { selection = nil }
        case .packs:
            PacksView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            ContentUnavailableView("Nothing selected", systemImage: "person.2",
                                   description: Text("Pick a session, a character or a room on the left."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func addRoom() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Choose Project")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { selection = .room(await model.addRoom(folder: url)) }
    }
}

/// Önizlemedeki tişört rengi: seçilen renk, yoksa verilen (proje) renk.
private func previewShirt(_ look: AvatarLook, fallback: AvatarLook.RGBA) -> AvatarLook.RGBA {
    look.colors.top?.rgba ?? look.shirtColor.map { AvatarLook.shirtColors[$0 % AvatarLook.shirtColors.count] } ?? fallback
}

private let neutralShirt: AvatarLook.RGBA = (0.30, 0.55, 0.95)

// MARK: - Oturum

/// Oturumun karakteri: kadrodan otomatik, rastgele görünüş ya da bir karakter. Karakteri varsa onu düzenler; yoksa
/// oturumun kendi görünüşü ("Karakter olarak kaydet" ile kalıcı olur).
private struct SessionDetail: View {
    @Bindable var model: AppModel
    let id: String
    let compact: Bool

    private var choice: Binding<String> {
        Binding(get: { model.records[id]?.characterID ?? "" },
                set: { model.setCharacter($0.isEmpty ? nil : $0, for: id) })
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Form {
                    Section {
                        Picker("Character", selection: choice) {
                            Text("Automatic (room cast)").tag("")
                            Text("Random look").tag(CastAssignment.random)
                            if !model.characters.isEmpty { Divider() }
                            ForEach(model.characters) { Text(verbatim: $0.label).tag($0.id) }
                        }
                        Text("Automatic picks the first free character of the room's cast; without a cast the session gets a random look.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .frame(height: 130)
                if let character = model.character(for: id) {
                    CharacterForm(model: model, id: character.id)
                } else {
                    Form {
                        LookSections(model: model, look: model.look(for: id), projectColor: model.projectColor(for: id)) {
                            model.setLook($0, for: id)
                        }
                        Section {
                            HStack {
                                Button("Save as Character") { model.saveAsCharacter(id) }
                                Button("Randomize") {
                                    var rng = SystemRandomNumberGenerator()
                                    model.setLook(AvatarLook.random(using: &rng), for: id)
                                }
                                Button("Reset to Default") { model.setLook(nil, for: id) }
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            .frame(minWidth: compact ? 250 : 380, maxWidth: .infinity)
            Divider()
            VillagerPreview(look: model.look(for: id), shirtColor: previewShirt(model.look(for: id), fallback: model.projectColor(for: id)), id: id)
                .frame(width: compact ? 170 : 260)
        }
    }
}

// MARK: - Karakter

private struct CharacterDetail: View {
    @Bindable var model: AppModel
    let id: String
    let compact: Bool
    let deleted: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                CharacterForm(model: model, id: id)
                HStack {
                    Button("Duplicate") { model.duplicateCharacter(id) }
                    Spacer()
                    Button("Delete Character", role: .destructive) { model.deleteCharacter(id); deleted() }
                }
                .padding(12)
            }
            .frame(minWidth: compact ? 250 : 380, maxWidth: .infinity)
            Divider()
            if let character = model.character(id: id) {
                VillagerPreview(look: character.look, shirtColor: previewShirt(character.look, fallback: neutralShirt), id: id)
                    .frame(width: compact ? 170 : 260)
            }
        }
    }
}

/// Karakterin bütün ayarları: isim, rol, görünüş, kişilik, imza ve odaları.
private struct CharacterForm: View {
    @Bindable var model: AppModel
    let id: String
    @State private var name = ""
    @State private var role = ""

    private var character: AgentCharacter? { model.character(id: id) }

    private func update(_ change: (inout AgentCharacter) -> Void) {
        guard var next = character else { return }
        change(&next)
        model.updateCharacter(next)
    }

    var body: some View {
        if let character {
            Form {
                Section {
                    TextField("Name", text: $name).onChange(of: name) {
                        if let trimmed = AvatarLook.trimmedName(name) { update { $0.name = trimmed } }
                    }
                    TextField("Role", text: $role, prompt: Text("e.g. frontend, tests")).onChange(of: role) {
                        update { $0.role = AvatarLook.trimmedName(role) }
                    }
                }
                LookSections(model: model, look: character.look, projectColor: nil) { look in update { $0.look = look } }
                PersonalitySection(personality: character.personality) { p in update { $0.personality = p } }
                SignatureSection(signature: character.signature) { s in update { $0.signature = s } }
                RoomsSection(model: model, characterID: id)
                Section {
                    Button("Randomize Look") {
                        var rng = SystemRandomNumberGenerator()
                        update { $0.look = AvatarLook.random(using: &rng) }
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear { name = character.name; role = character.role ?? "" }
            .onChange(of: id) { name = self.character?.name ?? ""; role = self.character?.role ?? "" }
        }
    }
}

private struct PersonalitySection: View {
    let personality: Personality
    let set: (Personality) -> Void

    var body: some View {
        Section {
            Picker("Walking pace", selection: Binding(get: { personality.pace }, set: { v in var p = personality; p.pace = v; set(p) })) {
                Text("Slow").tag(Personality.Pace.slow)
                Text("Normal").tag(Personality.Pace.normal)
                Text("Brisk").tag(Personality.Pace.brisk)
            }
            .pickerStyle(.segmented)
            ForEach(RoomSpot.Kind.allCases, id: \.self) { kind in
                Picker(RoomStyleSections.furnitureName(RoomFurniture(rawValue: kind.rawValue)!),
                       selection: Binding(get: { personality.weight(kind) }, set: { v in var p = personality; p.favorites[kind] = v; set(p) })) {
                    Text("Never").tag(0)
                    Text("Sometimes").tag(1)
                    Text("Often").tag(2)
                    Text("Loves it").tag(3)
                }
            }
        } header: {
            Text("Personality")
        } footer: {
            Text("When idle, the villager walks to the things it likes more often.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct SignatureSection: View {
    let signature: Signature
    let set: (Signature) -> Void

    var body: some View {
        Section("Signature") {
            Picker("Celebration", selection: Binding(get: { signature.celebration }, set: { v in var s = signature; s.celebration = v; set(s) })) {
                Text("Cheer").tag(Signature.Celebration.cheer)
                Text("Bow").tag(Signature.Celebration.bow)
                Text("Peace sign").tag(Signature.Celebration.peace)
            }
            Picker("Resting face", selection: Binding(get: { signature.restingMouth }, set: { v in var s = signature; s.restingMouth = v; set(s) })) {
                Text("Same as the look").tag(AvatarLook.Mouth?.none)
                ForEach(AvatarLook.Mouth.allCases, id: \.self) { Text(LookSections.name($0)).tag(AvatarLook.Mouth?.some($0)) }
            }
        }
    }
}

/// Karakterin bulunduğu odalar (kadrolar): aç/kapa.
private struct RoomsSection: View {
    @Bindable var model: AppModel
    let characterID: String

    var body: some View {
        let keys = Array(Set(model.rooms.keys).union(model.store.sessions.map { model.roomKey(for: $0.cwd) })).sorted()
        if !keys.isEmpty {
            Section("Rooms") {
                ForEach(keys, id: \.self) { key in
                    Toggle(isOn: Binding(get: { model.room(for: key).cast.contains(characterID) }, set: { on in
                        var room = model.room(for: key)
                        if on { if !room.cast.contains(characterID) { room.cast.append(characterID) } } else { room.cast.removeAll { $0 == characterID } }
                        model.setRoom(room, for: key)
                    })) { Text(verbatim: model.roomName(for: key)) }
                }
            }
        }
    }
}

// MARK: - Görünüş

/// Görünüşün bölümleri (saç, yüz, kıyafet, aksesuar): palet renkleri + serbest renk seçici. Oturum ve karakter
/// formlarında ortak.
struct LookSections: View {
    @Bindable var model: AppModel
    let look: AvatarLook
    /// Oturumda proje rengi (tişört "proje rengi" seçilebilir); karakterde nil.
    let projectColor: AvatarLook.RGBA?
    let set: (AvatarLook) -> Void

    private func update(_ change: (inout AvatarLook) -> Void) {
        var next = look
        change(&next)
        set(next)
    }

    private func binding<T>(_ key: WritableKeyPath<AvatarLook, T>) -> Binding<T> {
        Binding(get: { look[keyPath: key] }, set: { value in update { $0[keyPath: key] = value } })
    }

    /// Serbest renk: seçilince paletin yerine geçer.
    private func custom(_ key: WritableKeyPath<AvatarLook.Colors, AvatarLook.Color?>, fallback: AvatarLook.RGBA) -> Binding<SwiftUI.Color> {
        Binding(get: {
            let c = look.colors[keyPath: key]?.rgba ?? fallback
            return SwiftUI.Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
        }, set: { color in
            guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return }
            update { $0.colors[keyPath: key] = AvatarLook.Color(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent)) }
        })
    }

    private var wardrobe: WardrobeCatalog { model.wardrobe }
    private var tops: [WardrobeCatalog.Entry] {
        wardrobe.tops.isEmpty ? AvatarLook.Top.allCases.map { .init(id: $0.rawValue, title: nil, onepiece: [.dress, .overalls].contains($0), design: false, colors: nil) } : wardrobe.tops
    }
    private var bottoms: [WardrobeCatalog.Entry] {
        wardrobe.bottoms.isEmpty ? AvatarLook.Bottom.allCases.map { .init(id: $0.rawValue, title: nil, onepiece: false, design: false, colors: nil) } : wardrobe.bottoms
    }
    private var shoes: [WardrobeCatalog.Entry] {
        wardrobe.shoes.isEmpty ? AvatarLook.Shoes.allCases.map { .init(id: $0.rawValue, title: nil, onepiece: false, design: false, colors: nil) } : wardrobe.shoes
    }
    private var top: WardrobeCatalog.Entry? { tops.first { $0.id == look.top } }

    var body: some View {
        Section("Hair") {
            Picker("Style", selection: binding(\.hairStyle)) {
                ForEach(AvatarLook.HairStyle.allCases, id: \.self) { Text(Self.name($0)).tag($0) }
            }
            LabeledContent("Color") {
                HStack(spacing: 6) {
                    Swatches(colors: AvatarLook.hairColors, selected: look.colors.hair == nil ? look.hairColor : -1) { i in
                        update { $0.hairColor = i; $0.colors.hair = nil }
                    }
                    ColorWell(selection: custom(\.hair, fallback: AvatarLook.hairColors[look.hairColor % AvatarLook.hairColors.count]))
                }
            }
        }
        Section("Face") {
            Picker("Eyes", selection: binding(\.eyes)) {
                ForEach(AvatarLook.Eyes.allCases, id: \.self) { Text(Self.name($0)).tag($0) }
            }
            Picker("Mouth", selection: binding(\.mouth)) {
                ForEach(AvatarLook.Mouth.allCases, id: \.self) { Text(Self.name($0)).tag($0) }
            }
            Toggle("Blush", isOn: binding(\.blush))
            LabeledContent("Skin tone") {
                HStack(spacing: 6) {
                    Swatches(colors: AvatarLook.skinTones, selected: look.colors.skin == nil ? look.skin : -1) { i in
                        update { $0.skin = i; $0.colors.skin = nil }
                    }
                    ColorWell(selection: custom(\.skin, fallback: AvatarLook.skinTones[look.skin % AvatarLook.skinTones.count]))
                }
            }
        }
        Section("Clothes") {
            Picker("Top", selection: binding(\.top)) { entries(tops, kind: .top) }
            if top?.design == true {
                LabeledContent("Design colors") {
                    HStack(spacing: 8) {
                        ColorWell(selection: custom(\.top, fallback: designColor(0)))
                        ColorWell(selection: custom(\.topSecondary, fallback: designColor(1)))
                        Button("Original") { update { $0.colors.top = nil; $0.colors.topSecondary = nil } }
                            .disabled(look.colors.top == nil && look.colors.topSecondary == nil)
                    }
                }
            } else {
                Picker("Pattern", selection: binding(\.shirtPattern)) {
                    ForEach(AvatarLook.ShirtPattern.allCases, id: \.self) { Text(Self.name($0)).tag($0) }
                }
                LabeledContent("Shirt color") {
                    HStack(spacing: 6) {
                        if let projectColor {
                            Swatch(color: projectColor, selected: look.shirtColor == nil && look.colors.top == nil,
                                   label: String(localized: "Project color")) { update { $0.shirtColor = nil; $0.colors.top = nil } }
                            Divider().frame(height: 18)
                        }
                        Swatches(colors: AvatarLook.shirtColors, selected: look.colors.top == nil ? (look.shirtColor ?? -1) : -1) { i in
                            update { $0.shirtColor = i; $0.colors.top = nil }
                        }
                        ColorWell(selection: custom(\.top, fallback: look.shirtColor.map { AvatarLook.shirtColors[$0 % AvatarLook.shirtColors.count] } ?? projectColor ?? neutralShirt))
                    }
                }
            }
            Picker("Bottoms", selection: binding(\.bottom)) { entries(bottoms, kind: .bottom) }
                .disabled(top?.onepiece == true)
            LabeledContent("Bottoms color") {
                HStack(spacing: 6) {
                    Swatches(colors: AvatarLook.pantsColors, selected: look.colors.bottom == nil ? look.pantsColor : -1) { i in
                        update { $0.pantsColor = i; $0.colors.bottom = nil }
                    }
                    ColorWell(selection: custom(\.bottom, fallback: AvatarLook.pantsColors[look.pantsColor % AvatarLook.pantsColors.count]))
                }
            }
            .disabled(top?.onepiece == true && look.top != AvatarLook.Top.overalls.rawValue)
            Picker("Shoes", selection: binding(\.shoes)) { entries(shoes, kind: .shoes) }
            LabeledContent("Shoe color") {
                HStack(spacing: 6) {
                    Swatches(colors: AvatarLook.shoeColors, selected: look.colors.shoes == nil ? look.shoeColor : -1) { i in
                        update { $0.shoeColor = i; $0.colors.shoes = nil }
                    }
                    ColorWell(selection: custom(\.shoes, fallback: AvatarLook.shoeColors[look.shoeColor % AvatarLook.shoeColors.count]))
                }
            }
        }
        Section("Accessories") {
            Picker("Hat", selection: binding(\.hat)) {
                ForEach(AvatarLook.Hat.allCases, id: \.self) { Text(Self.name($0)).tag($0) }
            }
            if look.hat != .none {
                LabeledContent("Hat color") {
                    HStack(spacing: 8) {
                        ColorWell(selection: custom(\.hat, fallback: look.colors.top?.rgba ?? neutralShirt))
                        Button("Match the top") { update { $0.colors.hat = nil } }.disabled(look.colors.hat == nil)
                    }
                }
            }
            Toggle("Glasses", isOn: binding(\.glasses))
        }
    }

    private func designColor(_ i: Int) -> AvatarLook.RGBA {
        let c = top?.colors?[safe: i] ?? [0.8, 0.8, 0.8]
        return (Double(c[0]), Double(c[1]), Double(c[2]))
    }

    enum Kind { case top, bottom, shoes }

    /// Temel öğeler önce; paket öğeleri pakete göre gruplu.
    @ViewBuilder private func entries(_ list: [WardrobeCatalog.Entry], kind: Kind) -> some View {
        ForEach(list.filter { $0.pack == nil }) { Text(Self.title($0, kind: kind)).tag($0.id) }
        let packs = Array(Set(list.compactMap(\.pack))).sorted()
        ForEach(packs, id: \.self) { pack in
            Divider()
            ForEach(list.filter { $0.pack == pack }) { Text(Self.title($0, kind: kind)).tag($0.id) }
        }
        // Seçili kimlik listede yoksa (paket kaldırıldı) Picker boş görünmesin.
        let current = kind == .top ? look.top : kind == .bottom ? look.bottom : look.shoes
        if !list.contains(where: { $0.id == current }) { Text(verbatim: current).tag(current) }
    }

    static func title(_ entry: WardrobeCatalog.Entry, kind: Kind) -> LocalizedStringKey {
        if let title = entry.title { return LocalizedStringKey(title) }
        switch kind {
        case .top: if let t = AvatarLook.Top(rawValue: entry.id) { return name(t) }
        case .bottom: if let b = AvatarLook.Bottom(rawValue: entry.id) { return name(b) }
        case .shoes: if let s = AvatarLook.Shoes(rawValue: entry.id) { return name(s) }
        }
        return LocalizedStringKey(entry.id)
    }

    static func name(_ style: AvatarLook.HairStyle) -> LocalizedStringKey {
        switch style {
        case .short: "Short"
        case .pigtails: "Pigtails"
        case .spiky: "Spiky"
        case .bob: "Bob"
        case .curly: "Curly"
        case .long: "Long"
        case .bun: "Bun"
        case .ponytail: "Ponytail"
        case .buzz: "Buzz cut"
        case .sidepart: "Side part"
        }
    }

    static func name(_ eyes: AvatarLook.Eyes) -> LocalizedStringKey {
        switch eyes {
        case .round: "Round"
        case .happy: "Happy"
        case .sleepy: "Sleepy"
        case .dot: "Dot"
        case .lashes: "Lashes"
        case .brows: "Eyebrows"
        }
    }

    static func name(_ pattern: AvatarLook.ShirtPattern) -> LocalizedStringKey {
        switch pattern {
        case .plain: "Plain"
        case .stripes: "Striped"
        case .dots: "Polka dots"
        case .plaid: "Plaid"
        case .check: "Checked"
        case .hearts: "Hearts"
        }
    }

    static func name(_ top: AvatarLook.Top) -> LocalizedStringKey {
        switch top {
        case .tee: "T-shirt"
        case .longsleeve: "Long sleeves"
        case .tank: "Tank top"
        case .sweater: "Sweater"
        case .dress: "Dress"
        case .overalls: "Overalls"
        }
    }

    static func name(_ bottom: AvatarLook.Bottom) -> LocalizedStringKey {
        switch bottom {
        case .pants: "Pants"
        case .shorts: "Shorts"
        case .skirt: "Skirt"
        }
    }

    static func name(_ shoes: AvatarLook.Shoes) -> LocalizedStringKey {
        switch shoes {
        case .sneakers: "Sneakers"
        case .boots: "Boots"
        case .slippers: "Slippers"
        }
    }

    static func name(_ mouth: AvatarLook.Mouth) -> LocalizedStringKey {
        switch mouth {
        case .smile: "Smile"
        case .open: "Laughing"
        case .flat: "Flat"
        }
    }

    static func name(_ hat: AvatarLook.Hat) -> LocalizedStringKey {
        switch hat {
        case .none: "None"
        case .beanie: "Beanie"
        case .cap: "Cap"
        case .headphones: "Headphones"
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Etiketsiz serbest renk seçici.
private struct ColorWell: View {
    @Binding var selection: SwiftUI.Color

    var body: some View {
        ColorPicker(selection: $selection, supportsOpacity: false) { EmptyView() }.labelsHidden()
    }
}

// MARK: - Oda

/// Odanın adı, projesi, kadrosu ve stili.
private struct RoomDetail: View {
    @Bindable var model: AppModel
    let roomKey: String
    let deleted: () -> Void
    @State private var name = ""

    private var room: RoomRecord { model.room(for: roomKey) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text(verbatim: (roomKey as NSString).lastPathComponent)).onChange(of: name) {
                        var next = room
                        next.name = AvatarLook.trimmedName(name)
                        model.setRoom(next, for: roomKey)
                    }
                    LabeledContent("Project") {
                        HStack {
                            Text(verbatim: (roomKey as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle)
                            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: roomKey)]) } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Section {
                    ForEach(room.cast, id: \.self) { id in
                        HStack {
                            Text(verbatim: model.character(id: id)?.label ?? "?")
                            Spacer()
                            Button { var next = room; next.cast.removeAll { $0 == id }; model.setRoom(next, for: roomKey) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onMove { from, to in var next = room; next.cast.move(fromOffsets: from, toOffset: to); model.setRoom(next, for: roomKey) }
                    Menu("Add Character") {
                        ForEach(model.characters.filter { !room.cast.contains($0.id) }) { character in
                            Button(character.label) { var next = room; next.cast.append(character.id); model.setRoom(next, for: roomKey) }
                        }
                        if !model.characters.isEmpty { Divider() }
                        Button("New Character") {
                            let id = model.addCharacter()
                            var next = room
                            next.cast.append(id)
                            model.setRoom(next, for: roomKey)
                        }
                    }
                } header: {
                    Text("Cast")
                } footer: {
                    Text("Sessions in this project take the first free character in this order. Without enough characters they get a random look.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                RoomStyleSections(model: model, roomKey: roomKey)
            }
            .formStyle(.grouped)
            HStack {
                Button("Reset Style") { model.setStyle(nil, for: roomKey) }
                Spacer()
                Button("Delete Room Settings", role: .destructive) { model.deleteRoom(roomKey); deleted() }
            }
            .padding(12)
        }
        .onAppear { name = room.name ?? "" }
        .onChange(of: roomKey) { name = room.name ?? "" }
    }
}

// MARK: - Paketler

private struct PacksView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                if model.packCatalog.isEmpty {
                    Text("No packs are available for this version.").foregroundStyle(.secondary)
                }
                ForEach(model.packCatalog) { pack in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: pack.title).font(.headline)
                            if let summary = pack.summary { Text(verbatim: summary).font(.caption).foregroundStyle(.secondary) }
                            Text(verbatim: "\(pack.version) · \(ByteCountFormatter.string(fromByteCount: Int64(pack.bytes), countStyle: .file))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.packDownloads.contains(pack.id) {
                            ProgressView().controlSize(.small)
                        } else if let installed = model.installedPacks[pack.id] {
                            if installed != pack.version {
                                Button("Update") { Task { await model.downloadPack(pack) } }
                            }
                            Button("Remove", role: .destructive) { Task { await model.removePack(pack.id) } }
                        } else {
                            Button("Download") { Task { await model.downloadPack(pack) } }
                        }
                    }
                }
            } header: {
                Text("Downloadable Packs")
            } footer: {
                Text("Packs add outfits and stay on this Mac only. Removing a pack keeps your characters; their clothes fall back to the closest built-in item.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await model.reloadPacks() }
    }
}

extension AgentCustomizer {
    /// `AgentOffice --customizer-snapshot <klasör>`: pencereyi (demo oturumlarla) ve önizlemenin birkaç anını PNG'ye
    /// çizer ve çıkar (gözle kontrol; Metal önizlemesi pencere görüntüsüne girmez, ayrıca çizilir).
    static func snapshot(arguments: [String], model: AppModel) async -> Bool {
        guard let index = arguments.firstIndex(of: "--customizer-snapshot"), index + 1 < arguments.count else { return false }
        let directory = URL(fileURLWithPath: arguments[index + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        model.loadDemoSessions()
        await model.reloadPacks()
        var rng = SeededGenerator(seed: 11)
        let ada = AgentCharacter(name: "Ada", role: "frontend", look: AvatarLook.random(using: &rng))
        model.characters = [ada, AgentCharacter(name: "Linus", role: "tests", look: AvatarLook.random(using: &rng))]
        let id = model.store.sessions.first?.id
        if let id { model.records[id]?.characterID = ada.id; model.refreshCast() }
        model.customizingAgent = id
        let host = NSHostingView(rootView: AgentCustomizer(model: model).frame(width: 1040, height: 700))
        host.frame = NSRect(x: 0, y: 0, width: 1040, height: 700)
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(600))
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("window.png"))
        }
        if let id {
            let look = model.look(for: id)
            let shirt = previewShirt(look, fallback: model.projectColor(for: id))
            for t in [0.5, 3.0, 9.0, 12.0] {
                guard let image = await VillagerPreviewNSView.renderOffscreen(
                    look: look, shirt: SIMD3(Float(shirt.red), Float(shirt.green), Float(shirt.blue)),
                    size: (520, 640), at: t) else { continue }
                let rep = NSBitmapImageRep(cgImage: image)
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("preview-\(Int(t)).png"))
            }
        }
        print("customizer snapshot: \(directory.path)")
        return true
    }
}
