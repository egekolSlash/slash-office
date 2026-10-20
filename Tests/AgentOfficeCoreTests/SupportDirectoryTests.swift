import Foundation
import Testing
@testable import AgentOfficeCore

/// Destek klasörü varsayılan olarak `Application Support/AgentOffice`; `AGENT_OFFICE_SUPPORT_DIR` ile değişir
/// (tanıtım kaydı gibi kullanıcının verisine dokunmaması gereken ayrı kopyalar için).
struct SupportDirectoryTests {
    @Test func defaultsToApplicationSupport() {
        let url = SupportDirectory.url(environment: [:])
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #expect(url == base.appendingPathComponent("AgentOffice", isDirectory: true))
    }

    @Test func environmentOverrides() {
        let url = SupportDirectory.url(environment: ["AGENT_OFFICE_SUPPORT_DIR": "/tmp/promo-support"])
        #expect(url.path == "/tmp/promo-support")
    }

    @Test func emptyOverrideIsIgnored() {
        #expect(SupportDirectory.url(environment: ["AGENT_OFFICE_SUPPORT_DIR": ""]) == SupportDirectory.url(environment: [:]))
    }
}
