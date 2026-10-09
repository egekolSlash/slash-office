/// Uygulamanın klavye kısayolları tek tabloda: menü ve rehber buradan beslenir. Oturum ve panel gezinmesi
/// ok tuşlarıyla (her klavye düzeninde aynı yerde); düzene göre yeri değişen noktalama kullanılmaz.
public struct Shortcut: Equatable, Sendable, Identifiable {
    public enum Key: Equatable, Sendable, CustomStringConvertible {
        case character(Character)
        case left, right, up, down, delete

        public var description: String {
            switch self {
            case .character(let c): String(c).uppercased()
            case .left: "←"
            case .right: "→"
            case .up: "↑"
            case .down: "↓"
            case .delete: "⌫"
            }
        }
    }

    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let shift = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)

        /// AppKit `NSEvent.ModifierFlags` ham değerinden (Caps Lock ve diğerleri yok sayılır).
        public init(eventFlags: UInt) {
            var modifiers: Modifiers = []
            if eventFlags & (1 << 18) != 0 { modifiers.insert(.control) }
            if eventFlags & (1 << 19) != 0 { modifiers.insert(.option) }
            if eventFlags & (1 << 17) != 0 { modifiers.insert(.shift) }
            if eventFlags & (1 << 20) != 0 { modifiers.insert(.command) }
            self = modifiers
        }
    }

    public enum Group: Sendable, CaseIterable { case sessions, panes, modes, text }

    public let id: String
    /// İngilizce başlık (String Catalog anahtarı).
    public let title: String
    public let key: Key
    public let modifiers: Modifiers
    public let group: Group

    public init(_ id: String, _ title: String, _ key: Key, _ modifiers: Modifiers = .command, _ group: Group) {
        self.id = id
        self.title = title
        self.key = key
        self.modifiers = modifiers
        self.group = group
    }

    /// Değiştiriciler Apple sırasıyla (⌃⌥⇧⌘), sonra tuş: "⇧⌘←".
    public var symbols: String { Self.modifierSymbols(modifiers) + key.description }

    public static func modifierSymbols(_ modifiers: Modifiers) -> String {
        [(Modifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { modifiers.contains($0.0) }.map(\.1).joined()
    }
}

public enum ShortcutCatalog {
    public static let all: [Shortcut] = [
        Shortcut("session.newClaude", "New Claude Session", .character("n"), .command, .sessions),
        Shortcut("pane.new", "New Pane", .character("t"), .command, .panes),
        Shortcut("pane.newBeside", "New Pane Beside", .character("d"), .command, .panes),
        Shortcut("mode.office", "Office", .character("1"), .command, .modes),
        Shortcut("mode.work", "Work", .character("2"), .command, .modes),
        Shortcut("mode.focus", "Focus", .character("3"), .command, .modes),
        Shortcut("text.bigger", "Bigger Text", .character("+"), .command, .text),
        Shortcut("text.smaller", "Smaller Text", .character("-"), .command, .text),
        Shortcut("text.actual", "Actual Size", .character("0"), .command, .text),
        Shortcut("session.jumpToWaiting", "Jump to Waiting Agent", .character("j"), .command, .sessions),
        Shortcut("session.previous", "Previous Session", .up, [.command, .shift], .sessions),
        Shortcut("session.next", "Next Session", .down, [.command, .shift], .sessions),
        Shortcut("pane.previous", "Previous Pane", .left, [.command, .shift], .panes),
        Shortcut("pane.next", "Next Pane", .right, [.command, .shift], .panes),
        Shortcut("session.resume", "Resume Session", .character("r"), .command, .sessions),
        Shortcut("session.removeStopped", "Remove Stopped Session", .delete, [.command, .shift], .sessions),
        Shortcut("session.resumeAll", "Resume All Stopped Sessions", .character("r"), [.command, .shift], .sessions),
        Shortcut("pane.close", "Close Pane", .character("w"), .command, .panes),
        Shortcut("agents.customize", "Customize Agents…", .character("a"), [.command, .shift], .sessions),
    ]

    public static func shortcut(_ id: String) -> Shortcut {
        guard let shortcut = all.first(where: { $0.id == id }) else { preconditionFailure("unknown shortcut \(id)") }
        return shortcut
    }

    /// ⌘= de yazıyı büyütür (menüde ⌘+ görünür; ABD klavyesinde + Shift ister). `=` Shift istiyorsa (Türkçe Q'da ⇧0)
    /// ⌘⇧= de kabul edilir.
    public static func isBiggerTextEquals(characters: String?, modifiers: Shortcut.Modifiers) -> Bool {
        characters == "=" && modifiers.contains(.command) && modifiers.isSubset(of: [.command, .shift])
    }

    /// Rehberde yazıyı büyütmenin bu düzende basılışı: ⌘ + `=`'nin yazıldığı tuş. Düzen bilinmiyorsa ⌘+.
    public static func biggerTextDisplay(equalsTyping: (modifiers: Shortcut.Modifiers, base: String)?) -> String {
        guard let equalsTyping else { return shortcut("text.bigger").symbols }
        return Shortcut.modifierSymbols(equalsTyping.modifiers.union(.command)) + equalsTyping.base.uppercased()
    }
}
