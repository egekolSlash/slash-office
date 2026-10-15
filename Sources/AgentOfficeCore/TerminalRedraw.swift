import Foundation

/// Terminalin ekrana çizilme sıklığı. Uygulama öndeyken penceredeki terminaller her değişikliği hemen çizer; enerji
/// tasarrufunda yalnız klavyesi olan terminal hemen çizer, diğerleri değişiklikleri biriktirip seyrek çizer (Claude'un
/// spinner'ı ve durum satırı saniyede birkaç kez değişir, her çizim satırları baştan dizgiler). Arka plandaki uygulama
/// hep seyrek çizer. Kaydırılan terminal her zaman hemen çizer (kaydırma takılmasın).
public enum TerminalRedraw {
    public static let unfocusedInterval: TimeInterval = 0.15
    public static let backgroundInterval: TimeInterval = 0.25
    /// Son kaydırmadan sonra bu kadar süre terminal hemen çizer.
    public static let scrollGrace: TimeInterval = 0.5

    /// nil: hemen çiz; değilse değişiklikler bu aralıkta bir kez çizilir.
    public static func interval(focused: Bool, appActive: Bool, energySaving: Bool, scrolling: Bool = false) -> TimeInterval? {
        if scrolling { return nil }
        guard appActive else { return backgroundInterval }
        return focused || !energySaving ? nil : unfocusedInterval
    }

    public static func isScrolling(lastScroll: Date?, now: Date) -> Bool {
        guard let lastScroll else { return false }
        return now.timeIntervalSince(lastScroll) < scrollGrace
    }
}
