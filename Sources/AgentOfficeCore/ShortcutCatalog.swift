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

    /// Değiştiriciler Apple sırasıyla (⌃⌥⇧⌘), sonra tuş: "⌥⌘←".
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
        Shortcut("session.previous", "Previous Session", .left, [.command, .option], .sessions),
        Shortcut("session.next", "Next Session", .right, [.command, .option], .sessions),
        Shortcut("pane.previous", "Previous Pane", .up, [.command, .option], .panes),
        Shortcut("pane.next", "Next Pane", .down, [.command, .option], .panes),
        Shortcut("session.resume", "Resume Session", .character("r"), .command, .sessions),
        Shortcut("session.removeStopped", "Remove Stopped Session", .delete, [.command, .shift], .sessions),
        Shortcut("session.resumeAll", "Resume All Stopped Sessions", .character("r"), [.command, .shift], .sessions),
        Shortcut("pane.close", "Close Pane", .character("w"), .command, .panes),
    ]

    public static func shortcut(_ id: String) -> Shortcut {
        guard let shortcut = all.first(where: { $0.id == id }) else { preconditionFailure("unknown shortcut \(id)") }
        return shortcut
    }
}
