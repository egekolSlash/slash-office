import Foundation

/// Telefondan gelen metin (spec §6): terminale yazmadan önce kontrol karakterleri atılır, böylece metin bracketed
/// paste'ten kaçıp tuş gönderemez. Satır sonları korunur; gönderme (`submit`) ayrıca yazılır.
public enum RemoteInput {
    public static let maxTextLength = 20_000
    public static let submit = "\r"
    public static let interrupt = "\u{1b}"

    public static func paste(_ text: String, bracketedPaste: Bool) -> String? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var scalars = String.UnicodeScalarView()
        for scalar in normalized.unicodeScalars where scalar == "\n" || scalar == "\t" || !isControl(scalar) {
            scalars.append(scalar)
        }
        let cleaned = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= maxTextLength else { return nil }
        guard bracketedPaste else { return cleaned.replacingOccurrences(of: "\n", with: " ") }
        return "\u{1b}[200~" + cleaned + "\u{1b}[201~"
    }

    static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || scalar.value == 0x7F || (0x80...0x9F).contains(scalar.value)
    }
}
