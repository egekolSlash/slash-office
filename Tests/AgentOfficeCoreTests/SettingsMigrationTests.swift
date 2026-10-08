import Foundation
import Testing
@testable import AgentOfficeCore

/// Bundle kimliği değişince eski ayarlar yeni kimliğe bir kez taşınır; yeni kimlikte ayar varsa dokunulmaz.
@Suite(.serialized) struct SettingsMigrationTests {
    let old = "test.slashoffice.old.\(UInt32.random(in: 0...UInt32.max))"
    let new = "test.slashoffice.new.\(UInt32.random(in: 0...UInt32.max))"

    @Test func copiesOldSettingsOnce() {
        let defaults = UserDefaults.standard
        defaults.setPersistentDomain(["richOffice": true, "recentProjects": ["/p"]], forName: old)
        defer { defaults.removePersistentDomain(forName: old); defaults.removePersistentDomain(forName: new) }
        SettingsMigration.run(defaults: defaults, bundleID: new, oldDomain: old)
        #expect(defaults.persistentDomain(forName: new)?["richOffice"] as? Bool == true)
        // Yeni kimlikte değişen ayar ikinci çalıştırmada ezilmez.
        defaults.setPersistentDomain(["richOffice": false], forName: new)
        SettingsMigration.run(defaults: defaults, bundleID: new, oldDomain: old)
        #expect(defaults.persistentDomain(forName: new)?["richOffice"] as? Bool == false)
    }

    @Test func nothingToCopy() {
        let defaults = UserDefaults.standard
        defer { defaults.removePersistentDomain(forName: new) }
        SettingsMigration.run(defaults: defaults, bundleID: new, oldDomain: old)
        #expect(defaults.persistentDomain(forName: new) == nil)
    }
}
