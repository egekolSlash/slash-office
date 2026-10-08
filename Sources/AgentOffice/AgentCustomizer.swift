import AgentOfficeCore
import SwiftUI

/// Köylü özelleştirme (ofis hayatı §C4): solda bütün köylüler, ortada ad ve bütün görünüm seçenekleri, sağda
/// köylünün kendisi canlı. Değişiklik anında kaydedilir ve ofise yansır. Pencerede ve rehberde (`compact`) kullanılır.
struct AgentCustomizer: View {
    @Bindable var model: AppModel
    var compact = false
    @State private var selection: String?

    var body: some View {
        HStack(spacing: 0) {
            List(model.store.sessions, selection: $selection) { session in
                HStack(spacing: 8) {
                    ProjectIconView(icon: model.projectIcons[session.cwd], size: 22, isShell: model.kind(of: session.id) == .shell)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: model.displayName(for: session.id)).font(.body.weight(.medium)).lineLimit(1)
                        if model.look(for: session.id).name != nil {
                            Text(verbatim: session.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .tag(session.id)
            }
            .frame(width: compact ? 170 : 220)
            Divider()
            if let id = selection, model.store.session(id) != nil {
                AgentEditorForm(model: model, id: id)
                    .frame(minWidth: compact ? 250 : 360, maxWidth: .infinity)
                Divider()
                VillagerPreview(look: model.look(for: id), shirtColor: model.shirtColor(for: id))
                    .frame(width: compact ? 170 : 260)
            } else {
                ContentUnavailableView("No agents yet", systemImage: "person.2",
                                       description: Text("Start a session and its villager appears here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { selection = model.customizingAgent ?? selection ?? model.store.sessions.first?.id }
        // "Edit Appearance…" seçimi getirir; listeden seçmek de geri yazar (aynı köylüye tekrar gelinebilsin).
        .onChange(of: model.customizingAgent) { if let id = model.customizingAgent { selection = id } }
        .onChange(of: selection) { if let selection { model.customizingAgent = selection } }
    }
}

/// Seçili köylünün adı ve görünüm seçenekleri.
private struct AgentEditorForm: View {
    @Bindable var model: AppModel
    let id: String
    @State private var name = ""

    private var look: AvatarLook { model.look(for: id) }

    private func update(_ change: (inout AvatarLook) -> Void) {
        var next = look
        change(&next)
        model.setLook(next, for: id)
    }

    private func binding<T>(_ key: WritableKeyPath<AvatarLook, T>) -> Binding<T> {
        Binding(get: { look[keyPath: key] }, set: { value in update { $0[keyPath: key] = value } })
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text(verbatim: model.store.session(id)?.title ?? ""))
                    .onChange(of: name) { update { $0.name = AvatarLook.trimmedName(name) } }
            }
            Section("Hair") {
                Picker("Style", selection: binding(\.hairStyle)) {
                    ForEach(AvatarLook.HairStyle.allCases, id: \.self) { Text(Self.name($0)).tag($0) }
                }
                LabeledContent("Color") {
                    Swatches(colors: AvatarLook.hairColors, selected: look.hairColor) { i in update { $0.hairColor = i } }
                }
            }
            Section("Face") {
                Picker("Eyes", selection: binding(\.eyes)) {
                    ForEach(AvatarLook.Eyes.allCases, id: \.self) { Text(Self.name($0)).tag($0) }
                }
                Picker("Eyebrows", selection: binding(\.brows)) {
                    ForEach(AvatarLook.Brows.allCases, id: \.self) { Text(Self.name($0)).tag($0) }
                }
                Picker("Mouth", selection: binding(\.mouth)) {
                    ForEach(AvatarLook.Mouth.allCases, id: \.self) { Text(Self.name($0)).tag($0) }
                }
                Toggle("Blush", isOn: binding(\.blush))
                Toggle("Freckles", isOn: binding(\.freckles))
                LabeledContent("Skin tone") {
                    Swatches(colors: AvatarLook.skinTones, selected: look.skin) { i in update { $0.skin = i } }
                }
            }
            Section("Clothes") {
                Picker("Shirt pattern", selection: binding(\.shirtPattern)) {
                    Text("Plain").tag(AvatarLook.ShirtPattern.plain)
                    Text("Striped").tag(AvatarLook.ShirtPattern.stripes)
                    Text("Polka dots").tag(AvatarLook.ShirtPattern.dots)
                }
                LabeledContent("Shirt color") {
                    HStack(spacing: 6) {
                        Swatch(color: model.projectColor(for: id), selected: look.shirtColor == nil,
                               label: String(localized: "Project color")) { update { $0.shirtColor = nil } }
                        Divider().frame(height: 18)
                        Swatches(colors: AvatarLook.shirtColors, selected: look.shirtColor ?? -1) { i in update { $0.shirtColor = i } }
                    }
                }
                LabeledContent("Pants") {
                    Swatches(colors: AvatarLook.pantsColors, selected: look.pantsColor) { i in update { $0.pantsColor = i } }
                }
                LabeledContent("Shoes") {
                    Swatches(colors: AvatarLook.shoeColors, selected: look.shoeColor) { i in update { $0.shoeColor = i } }
                }
            }
            Section("Accessories") {
                Picker("Hat", selection: binding(\.hat)) {
                    ForEach(AvatarLook.Hat.allCases, id: \.self) { Text(Self.name($0)).tag($0) }
                }
                Toggle("Glasses", isOn: binding(\.glasses))
            }
            Section {
                HStack {
                    Button("Randomize") {
                        var rng = SystemRandomNumberGenerator()
                        var next = AvatarLook.random(using: &rng)
                        next.name = look.name   // ad korunur
                        model.setLook(next, for: id)
                    }
                    Button("Reset to Default") {
                        var reset = AvatarLook.default(for: id)
                        reset.name = look.name
                        model.setLook(reset, for: id)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { name = look.name ?? "" }
        .onChange(of: id) { name = look.name ?? "" }
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
        }
    }

    static func name(_ eyes: AvatarLook.Eyes) -> LocalizedStringKey {
        switch eyes {
        case .round: "Round"
        case .happy: "Happy"
        case .sleepy: "Sleepy"
        }
    }

    static func name(_ brows: AvatarLook.Brows) -> LocalizedStringKey {
        switch brows {
        case .none: "None"
        case .thin: "Thin"
        case .bold: "Bold"
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

extension AgentCustomizer {
    /// `AgentOffice --customizer-snapshot <klasör>`: pencereyi (demo oturumlarla) ve önizlemenin birkaç anını PNG'ye
    /// çizer ve çıkar (gözle kontrol; Metal önizlemesi pencere görüntüsüne girmez, ayrıca çizilir).
    static func snapshot(arguments: [String], model: AppModel) async -> Bool {
        guard let index = arguments.firstIndex(of: "--customizer-snapshot"), index + 1 < arguments.count else { return false }
        let directory = URL(fileURLWithPath: arguments[index + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        model.loadDemoSessions()
        var rng = SeededGenerator(seed: 11)
        for session in model.store.sessions { model.avatarLooks[session.id] = AvatarLook.random(using: &rng) }
        let id = model.store.sessions.first?.id
        if let id { var look = model.look(for: id); look.name = "Ada"; model.avatarLooks[id] = look }
        model.customizingAgent = id
        let host = NSHostingView(rootView: AgentCustomizer(model: model).frame(width: 980, height: 640))
        host.frame = NSRect(x: 0, y: 0, width: 980, height: 640)
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
            let shirt = model.shirtColor(for: id)
            for t in [0.5, 3.0, 9.0, 12.0] {
                guard let image = await VillagerPreviewNSView.renderOffscreen(
                    look: model.look(for: id), shirt: SIMD3(Float(shirt.red), Float(shirt.green), Float(shirt.blue)),
                    size: (520, 640), at: t) else { continue }
                let rep = NSBitmapImageRep(cgImage: image)
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("preview-\(Int(t)).png"))
            }
        }
        print("customizer snapshot: \(directory.path)")
        return true
    }
}
