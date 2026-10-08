import AgentOfficeCore
import AppKit
import SwiftUI

/// İlk açılış rehberi (spec §4): dil, Claude Code, izinler, ofis, tercihler, kısayollar, ilk oturum. Her adımda
/// atlanabilir; her şey sonradan Ayarlar'dan değişir.
struct OnboardingView: View {
    @Bindable var model: AppModel
    @State private var guide: Onboarding

    init(model: AppModel, step: Onboarding.Step? = nil) {
        self.model = model
        let defaults = UserDefaults.standard
        let saved = step?.rawValue ?? defaults.object(forKey: Onboarding.stepKey) as? Int
        _guide = State(initialValue: model.onboardingReopened && step == nil
            ? .reopened()
            : Onboarding(savedStep: saved, completed: false))
    }

    /// `AgentOffice --onboarding-snapshot <klasör>`: her adımı ekran dışında PNG'ye çizer ve çıkar (gözle kontrol).
    static func snapshot(arguments: [String], model: AppModel) -> Bool {
        guard let index = arguments.firstIndex(of: "--onboarding-snapshot"), index + 1 < arguments.count else { return false }
        let directory = URL(fileURLWithPath: arguments[index + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for step in Onboarding.Step.allCases {
            let host = NSHostingView(rootView: OnboardingView(model: model, step: step))
            host.frame = NSRect(x: 0, y: 0, width: 620, height: 540)
            // Arka plan saydam: koyu modda beyaz metin PNG'de kaybolmasın.
            host.appearance = NSAppearance(named: .aqua)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(step == .claude ? 1.5 : 0.3))
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let url = directory.appendingPathComponent("\(step.rawValue)-\(step).png")
            try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
            print("onboarding snapshot: \(url.path)")
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            StepDots(current: guide.current)
                .padding(.top, 18)
            ScrollView {
                step
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 20)
            }
            Divider()
            HStack {
                Button("Skip") { finish { $0.skip() } }
                Spacer()
                if !guide.isFirst { Button("Back") { guide.back() } }
                Button(guide.isLast ? "Finish" : "Continue") { finish { $0.next() } }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 620, height: 540)
        .onChange(of: guide.current) { UserDefaults.standard.set(guide.savedStep, forKey: Onboarding.stepKey) }
    }

    /// Adımı uygular; rehber tamamlandıysa kaydeder ve kapanır.
    private func finish(_ change: (inout Onboarding) -> Void) {
        change(&guide)
        guard guide.isCompleted else { return }
        UserDefaults.standard.set(true, forKey: Onboarding.completedKey)
        UserDefaults.standard.removeObject(forKey: Onboarding.stepKey)
        model.onboardingReopened = false
        model.showOnboarding = false
    }

    @ViewBuilder private var step: some View {
        switch guide.current {
        case .language: LanguageStep(model: model, guide: $guide)
        case .claude: ClaudeStep(model: model)
        case .permissions: PermissionsStep()
        case .office: OfficeStep()
        case .preferences: PreferencesStep()
        case .shortcuts: ShortcutsStep()
        case .firstSession: FirstSessionStep(model: model) { finish { $0.skip() } }
        }
    }
}

private struct StepDots: View {
    let current: Onboarding.Step

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Onboarding.Step.allCases, id: \.self) { step in
                Circle()
                    .fill(step == current ? Color.accentColor : Color.secondary.opacity(step.rawValue < current.rawValue ? 0.6 : 0.25))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

/// Adım başlığı ve açıklaması.
private struct StepHeader: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(Color.accentColor)
            Text(title).font(.title.bold())
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 12)
    }
}

private struct LanguageStep: View {
    let model: AppModel
    @Binding var guide: Onboarding
    @State private var language = AppRestart.language

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(symbol: "globe", title: "Welcome to Slash Office",
                       detail: "Slash Office runs Claude Code and terminal sessions side by side and shows your agents working in a little office. Let's set it up — it takes a minute, and you can skip any step.")
            Picker("Language", selection: $language) {
                ForEach(AppLanguage.allCases, id: \.self) { option in
                    if option == .system { Text("System") } else { Text(verbatim: option.displayName) }
                }
            }
            .pickerStyle(.radioGroup)
            // Seçim hemen kaydedilir: Continue'ya basılsa da sonraki açılışta geçerli olur.
            .onChange(of: language) { AppRestart.apply(language) }
            if language.needsRestart(launched: AppRestart.launchedLanguage) {
                HStack {
                    Text("Slash Office restarts to switch the language, then continues from the next step.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Restart") {
                        // Sadece onaylanınca: açılışta rehber sonraki adımdan devam eder.
                        AppRestart.relaunch(runningAgents: model.runningAgentCount) {
                            let state = guide.stateForRestart
                            UserDefaults.standard.set(state.step, forKey: Onboarding.stepKey)
                            UserDefaults.standard.set(state.completed, forKey: Onboarding.completedKey)
                        }
                    }
                }
            }
        }
    }
}

private struct ClaudeStep: View {
    let model: AppModel
    @State private var status: (path: String?, version: String?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(symbol: "sparkles", title: "Claude Code",
                       detail: "Slash Office starts Claude Code in its panes and follows what each agent is doing. Without it, Slash Office still works as a terminal.")
            switch status {
            case nil:
                ProgressView().controlSize(.small)
            case let (path?, version)?:
                Label {
                    VStack(alignment: .leading) {
                        if let version { Text("Found Claude Code \(version)") } else { Text("Found Claude Code (version unknown)") }
                        Text(verbatim: path).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            case (nil, _)?:
                Label("Claude Code isn't installed.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Link("How to install Claude Code", destination: URL(string: "https://docs.anthropic.com/en/docs/claude-code")!)
                Button("Check Again") { Task { await check() } }
            }
        }
        .task { await check() }
    }

    private func check() async {
        status = nil
        status = await model.claudeStatus()
    }
}

private struct PermissionsStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StepHeader(symbol: "lock.shield", title: "Permissions",
                       detail: "Grant these now so macOS doesn't interrupt your agents later. All are optional.")
            PermissionsList()
        }
    }
}

private struct OfficeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(symbol: "building.2", title: "Meet the office",
                       detail: "Every project gets a room and every session a villager at a desk. Their pose tells you what the agent is doing.")
            LegendRow(symbol: "keyboard", color: .blue, title: "Working", detail: "Typing at the desk while the agent runs tools.")
            LegendRow(symbol: "questionmark.bubble.fill", color: .orange, title: "Asking",
                      detail: "Standing with a ? when the agent has a question or needs permission. You also get a notification.")
            LegendRow(symbol: "checkmark.seal.fill", color: .green, title: "Done",
                      detail: "A ✓ when the agent finished while you weren't looking.")
            LegendRow(symbol: "moon.zzz", color: .gray, title: "Idle", detail: "Dozing at the desk or wandering around the room.")
            LegendRow(symbol: "xmark.circle", color: .secondary, title: "Stopped", detail: "The session isn't running; resume it from its pane.")
            Text("Click a villager to open its terminal, ⇧-click to open it beside the current pane, click an empty lot to start a new session.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }
}

private struct LegendRow: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PreferencesStep: View {
    @AppStorage("richOffice") private var richOffice = false
    @AppStorage(OfficeMetalView.dayNightKey) private var dayNight = true
    @AppStorage(OfficeView.autoFocusKey) private var autoFocus = true
    @AppStorage(OfficeMetalView.energySavingKey) private var energySaving = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(symbol: "slider.horizontal.3", title: "Office preferences",
                       detail: "You can change these any time in Settings (⌘,).")
            PreferenceToggle(isOn: $richOffice, title: "Office view",
                             detail: "A 3D office you can pan and zoom, with animated villagers. Off: simple cards (less CPU and GPU).")
            PreferenceToggle(isOn: $dayNight, title: "Day and night", enabled: richOffice,
                             detail: "The sky follows your Mac's clock: sunrise, daylight, sunset and a starry night.")
            PreferenceToggle(isOn: $autoFocus, title: "Mini office auto-focus", enabled: richOffice,
                             detail: "In Work mode the small office turns to the agent that needs you: a question first, then a finished task, then a working agent.")
            PreferenceToggle(isOn: $energySaving, title: "Energy saving", enabled: richOffice,
                             detail: "On: villagers animate at 12–30 fps. Off: always at your display's refresh rate — smoother, uses more CPU.")
        }
    }
}

private struct PreferenceToggle: View {
    @Binding var isOn: Bool
    let title: LocalizedStringKey
    var enabled = true
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: $isOn).font(.headline).disabled(!enabled)
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 20)
        }
    }
}

private struct ShortcutsStep: View {
    @State private var layout = KeyboardLayout.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepHeader(symbol: "command", title: "Shortcuts",
                       detail: "Shown for your keyboard layout. All of them are also in the Agents menu.")
            if !layout.name.isEmpty {
                Text("Keyboard: \(layout.name)").font(.callout).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                ForEach(ShortcutCatalog.all) { shortcut in
                    GridRow {
                        Text(LocalizedStringKey(shortcut.title))
                        Text(verbatim: layout.display(shortcut)).font(.body.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct FirstSessionStep: View {
    let model: AppModel
    let done: () -> Void
    @State private var hasClaude = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(symbol: "play.circle", title: "You're all set",
                       detail: "Start your first session in a project folder, or finish and explore. ⌘N starts a new Claude session any time.")
            if hasClaude {
                Button("Choose a Folder and Start Claude") {
                    done()
                    model.chooseFolderAndStart(.claude)
                }
                .controlSize(.large)
            } else {
                Button("Open a Terminal") {
                    done()
                    model.newShellSession(cwd: URL(fileURLWithPath: NSHomeDirectory()))
                }
                .controlSize(.large)
            }
        }
        .task { hasClaude = model.findClaude() != nil }
    }
}
