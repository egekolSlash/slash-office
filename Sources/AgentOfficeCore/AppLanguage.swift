/// Uygulamanın dili: sistemin dili ya da uygulamaya özel İngilizce / Türkçe. macOS'ta uygulamaya özel dil,
/// uygulamanın kendi ayarlarındaki `AppleLanguages` ile seçilir ve yeniden başlatınca geçerli olur.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system, english, turkish

    /// Uygulamanın `AppleLanguages` değeri; sistem için nil (ayar silinir).
    public var appleLanguages: [String]? {
        switch self {
        case .system: nil
        case .english: ["en"]
        case .turkish: ["tr"]
        }
    }

    /// Uygulamaya özel ayardan seçim: ilk tanınan dil; yoksa sistem.
    public static func from(appleLanguages: [String]?) -> AppLanguage {
        for code in appleLanguages ?? [] {
            let base = code.split(separator: "-").first.map(String.init) ?? code
            if base == "en" { return .english }
            if base == "tr" { return .turkish }
            return .system
        }
        return .system
    }

    /// Dil adı kendi dilinde (çevrilmez); sistem seçeneğinin adı arayüzde çevrilir.
    public var displayName: String {
        switch self {
        case .system: "System"
        case .english: "English"
        case .turkish: "T\u{FC}rk\u{E7}e"
        }
    }
}
