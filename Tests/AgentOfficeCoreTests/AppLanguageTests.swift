import Testing
@testable import AgentOfficeCore

@Suite struct AppLanguageTests {
    @Test func roundTrip() {
        for language in AppLanguage.allCases {
            #expect(AppLanguage.from(appleLanguages: language.appleLanguages) == language)
        }
        #expect(AppLanguage.english.appleLanguages == ["en"])
        #expect(AppLanguage.turkish.appleLanguages == ["tr"])
        #expect(AppLanguage.system.appleLanguages == nil)
    }

    @Test func unknownListIsSystem() {
        #expect(AppLanguage.from(appleLanguages: ["de"]) == .system)
        #expect(AppLanguage.from(appleLanguages: nil) == .system)
        #expect(AppLanguage.from(appleLanguages: []) == .system)
    }

    @Test func firstMatchingLanguageWins() {
        #expect(AppLanguage.from(appleLanguages: ["tr-TR", "en"]) == .turkish)
        #expect(AppLanguage.from(appleLanguages: ["en-GB"]) == .english)
    }

    /// Dil adları her dilde kendi adıyla gösterilir (çevrilmez).
    @Test func displayNames() {
        #expect(AppLanguage.english.displayName == "English")
        #expect(AppLanguage.turkish.displayName == "Türkçe")
    }
}
