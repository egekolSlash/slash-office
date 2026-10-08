import Foundation
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

    /// Seçim hemen kaydedilir (rehberde Restart yerine Continue'ya basılsa da sonraki açılışta geçerli); sistem
    /// seçilince uygulamaya özel ayar silinir.
    @Test func storeWritesTheAppSpecificSetting() throws {
        let suite = "test.slashoffice.language.\(UInt32.random(in: 0...UInt32.max))"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        AppLanguage.turkish.store(in: defaults)
        #expect(AppLanguage.stored(in: defaults, domain: suite) == .turkish)
        AppLanguage.system.store(in: defaults)
        #expect(AppLanguage.stored(in: defaults, domain: suite) == .system)
        #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
    }

    /// Ayarlar'daki "Restart Now" sadece seçim açılıştaki dilden farklıyken görünür.
    @Test func needsRestartOnlyWhenDifferentFromLaunch() {
        #expect(AppLanguage.turkish.needsRestart(launched: .english))
        #expect(!AppLanguage.english.needsRestart(launched: .english))
        #expect(!AppLanguage.system.needsRestart(launched: .system))
    }
}

