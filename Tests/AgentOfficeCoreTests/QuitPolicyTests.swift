import Testing
@testable import AgentOfficeCore

/// Yeniden başlatma: kullanıcı onayladıysa çıkışta ikinci kez sorulmaz (sorulup iptal edilirse uygulama açık kalır
/// ama bekleyen yeniden açıcı saatler sonra uygulamayı kendiliğinden açardı).
@Suite struct QuitPolicyTests {
    @Test func asksOnlyWhenAgentsAreActiveAndNoRelaunchWasConfirmed() {
        #expect(QuitPolicy.asksBeforeQuit(activeAgents: true, relaunchConfirmed: false))
        #expect(!QuitPolicy.asksBeforeQuit(activeAgents: true, relaunchConfirmed: true))
        #expect(!QuitPolicy.asksBeforeQuit(activeAgents: false, relaunchConfirmed: false))
    }

    /// Yeniden açıcı yalnızca çıkış kesinleşince ve yeniden başlatma istendiyse başlar.
    @Test func relauncherStartsOnlyOnConfirmedTermination() {
        #expect(QuitPolicy.startsRelauncher(relaunchConfirmed: true))
        #expect(!QuitPolicy.startsRelauncher(relaunchConfirmed: false))
    }
}
