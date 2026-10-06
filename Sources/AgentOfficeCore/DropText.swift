/// Terminale sürüklenen dosyaların yazılacak metni (Ghostty gibi): kabukta özel anlamı olan karakterler `\` ile
/// kaçırılır, yollar boşlukla ayrılır. Claude bu yolları dosya referansı (görselleri `[Image #n]`) olarak alır.
public enum DropText {
    private static let special = Set(" \t\\'\"`$&|;<>()[]{}*?!#")

    public static func text(forPaths paths: [String]) -> String {
        paths.map { path in
            path.map { special.contains($0) ? "\\\($0)" : String($0) }.joined()
        }.joined(separator: " ")
    }
}
