import Foundation

/// Uygulamanın veri klasörü (oturum kayıtları, hook soketi, paketler). Varsayılanı `Application Support/AgentOffice`;
/// `AGENT_OFFICE_SUPPORT_DIR` ile ayrı bir klasör verilebilir: tanıtım kaydı gibi ayrı bir kopya kullanıcının
/// verisine ve açık uygulamanın soketine dokunmadan çalışır.
public enum SupportDirectory {
    public static let environmentKey = "AGENT_OFFICE_SUPPORT_DIR"

    public static let current = url(environment: ProcessInfo.processInfo.environment)

    public static func url(environment: [String: String]) -> URL {
        if let path = environment[environmentKey], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentOffice", isDirectory: true)
    }
}
