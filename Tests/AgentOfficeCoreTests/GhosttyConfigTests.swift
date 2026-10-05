import Testing
@testable import AgentOfficeCore

@Suite struct GhosttyConfigTests {
    @Test func configOverridesThemeAndSkipsComments() {
        let config = """
        # yorum
        theme = Night
        font-size = 15
        font-family = "Fira Code"
        font-family = Symbols Nerd Font
        foreground = #010203
        palette = 1=#ff0000
        window-padding-x = 8
        """
        let theme = "background = #111111\nforeground = #222222\npalette = 2=#00ff00\ncursor-color = #333333"
        let appearance = GhosttyConfig.appearance(config: config) { $0 == "Night" ? theme : nil }
        #expect(appearance.fontSize == 15)
        #expect(appearance.fontFamily == "Fira Code")
        #expect(appearance.background == RGB(hex: "#111111"))
        #expect(appearance.foreground == RGB(red: 1, green: 2, blue: 3))
        #expect(appearance.cursor == RGB(hex: "#333333"))
        #expect(appearance.palette[1] == RGB(hex: "#ff0000"))
        #expect(appearance.palette[2] == RGB(hex: "#00ff00"))
        #expect(appearance.paddingX == 8)
    }

    @Test func picksDarkVariantOfThemePair() {
        #expect(GhosttyConfig.themeName("light:Latte,dark:Mocha") == "Mocha")
        #expect(GhosttyConfig.themeName("Catppuccin Mocha") == "Catppuccin Mocha")
    }

    @Test func missingConfigKeepsDefaults() {
        let appearance = GhosttyConfig.appearance(config: nil) { _ in nil }
        #expect(appearance == TerminalAppearance())
        #expect(!appearance.optionAsAlt)
    }

    @Test func optionAsAltValues() {
        #expect(GhosttyConfig.appearance(config: "macos-option-as-alt = left") { _ in nil }.optionAsAlt)
        #expect(!GhosttyConfig.appearance(config: "macos-option-as-alt = false") { _ in nil }.optionAsAlt)
    }
}
