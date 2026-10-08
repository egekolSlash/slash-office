import Testing
@testable import AgentOfficeCore

@Suite struct OnboardingTests {
    @Test func walksForwardAndBack() {
        var guide = Onboarding(savedStep: nil, completed: false)
        #expect(guide.current == .language && guide.isFirst && !guide.isLast)
        guide.back()
        #expect(guide.current == .language)
        guide.next()
        #expect(guide.current == .claude)
        guide.back()
        #expect(guide.current == .language)
        for _ in 0..<4 { guide.next() }
        #expect(guide.current == .preferences)
        guide.next()
        #expect(guide.current == .agents)
        guide.next()
        #expect(guide.current == .shortcuts)
        guide.next()
        #expect(guide.current == .firstSession && guide.isLast && !guide.isCompleted)
    }

    @Test func lastNextCompletes() {
        var guide = Onboarding(savedStep: Onboarding.Step.firstSession.rawValue, completed: false)
        guide.next()
        #expect(guide.isCompleted)
    }

    @Test func skipCompletes() {
        var guide = Onboarding(savedStep: nil, completed: false)
        guide.next()
        guide.skip()
        #expect(guide.isCompleted)
    }

    /// Rehberde dil değişip uygulama yeniden açılınca dil adımına dönmez, sonraki adımdan devam eder.
    @Test func resumesAfterLanguageRestart() {
        var before = Onboarding(savedStep: nil, completed: false)
        before.resumeAfterRestart()
        let after = Onboarding(savedStep: before.savedStep, completed: false)
        #expect(after.current == .claude && !after.isCompleted)
    }

    /// Bir kez bitirilen (ya da atlanan) rehber bir daha kendiliğinden açılmaz.
    @Test func completedStaysCompleted() {
        let guide = Onboarding(savedStep: 3, completed: true)
        #expect(guide.isCompleted)
    }

    @Test func savedStepOutOfRangeStartsOver() {
        #expect(Onboarding(savedStep: 99, completed: false).current == .language)
        #expect(Onboarding(savedStep: -1, completed: false).current == .language)
    }

    /// "Help > Welcome Guide…" ile baştan açılır, tamamlanmış olsa da.
    @Test func reopenStartsFromTheBeginning() {
        let guide = Onboarding.reopened()
        #expect(guide.current == .language && !guide.isCompleted)
    }

    /// Help'ten yeniden açılan (tamamlanmış) rehberde dil değişip uygulama yeniden başlarsa rehber yine açılır ve
    /// dil adımından sonraki adımdan devam eder.
    @Test func reopenedGuideComesBackAfterLanguageRestart() {
        let saved = Onboarding.reopened().stateForRestart
        #expect(saved.completed == false)
        let after = Onboarding(savedStep: saved.step, completed: saved.completed)
        #expect(after.current == .claude && !after.isCompleted)
    }
}

