/// İlk açılış rehberinin adım akışı: ileri, geri, atla ve dil değişince yeniden başlatmadan sonra kaldığı yerden
/// devam. Bitirmek de atlamak da rehberi tamamlanmış sayar; bir daha kendiliğinden açılmaz.
public struct Onboarding: Equatable, Sendable {
    public enum Step: Int, CaseIterable, Sendable {
        case language, claude, permissions, office, preferences, shortcuts, firstSession
    }

    public static let completedKey = "onboardingCompleted"
    public static let stepKey = "onboardingStep"

    public private(set) var current: Step
    public private(set) var isCompleted: Bool

    public init(savedStep: Int?, completed: Bool) {
        current = savedStep.flatMap(Step.init(rawValue:)) ?? .language
        isCompleted = completed
    }

    /// Help menüsünden: baştan.
    public static func reopened() -> Onboarding { Onboarding(savedStep: nil, completed: false) }

    public var isFirst: Bool { current == Step.allCases.first }
    public var isLast: Bool { current == Step.allCases.last }
    /// Kaydedilecek adım (yeniden açılışta buradan devam).
    public var savedStep: Int { current.rawValue }

    public mutating func next() {
        if let following = Step(rawValue: current.rawValue + 1) { current = following } else { isCompleted = true }
    }

    public mutating func back() {
        if let previous = Step(rawValue: current.rawValue - 1) { current = previous }
    }

    public mutating func skip() { isCompleted = true }

    /// Dil seçilip yeniden başlatılacak: açılışta dil adımından sonraki adım gösterilsin.
    public mutating func resumeAfterRestart() {
        if current == .language { next() }
    }
}
