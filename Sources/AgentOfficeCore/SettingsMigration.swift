import Foundation

/// 0.1.0'da bundle kimliği `dev.agentoffice.app`'ten değişti: eski ayarlar (ofis görünümü, son projeler, yazı
/// boyutu…) yeni kimliğe bir kez taşınır; yeni kimlikte ayar varsa dokunulmaz. Oturum kayıtları uygulama adına
/// göre tutulduğu için etkilenmez.
public enum SettingsMigration {
    public static let oldDomain = "dev.agentoffice.app"

    public static func run(defaults: UserDefaults = .standard, bundleID: String?, oldDomain: String = oldDomain) {
        guard let bundleID, bundleID != oldDomain,
              defaults.persistentDomain(forName: bundleID)?.isEmpty ?? true,
              let old = defaults.persistentDomain(forName: oldDomain), !old.isEmpty else { return }
        defaults.setPersistentDomain(old, forName: bundleID)
    }
}
