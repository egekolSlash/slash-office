/// Çıkışta sorulup sorulmayacağı ve yeniden başlatmanın ne zaman kurulacağı. Yeniden başlatmayı kullanıcı zaten
/// onayladıysa (çalışan ajan uyarısıyla) çıkışta ikinci kez sorulmaz; yeniden açıcı da ancak çıkış kesinleşince
/// başlar — iptal edilen bir çıkıştan sonra uygulamayı saatler sonra kendiliğinden açmasın.
public enum QuitPolicy {
    public static func asksBeforeQuit(activeAgents: Bool, relaunchConfirmed: Bool) -> Bool {
        activeAgents && !relaunchConfirmed
    }

    public static func startsRelauncher(relaunchConfirmed: Bool) -> Bool { relaunchConfirmed }
}
