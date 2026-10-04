import Foundation

/// GUI'den açılan uygulamanın PATH'i kısıtlıdır (`.zshrc` okunmaz); npm/nvm/bun ile kurulan `claude`
/// ve ihtiyaç duyduğu `node` bulunamaz. Kullanıcının etkileşimli login shell'indeki PATH bir kez alınır.
public enum ShellPath {
    static let beginMarker = "__AO_PATH_BEGIN__"
    static let endMarker = "__AO_PATH_END__"

    /// Shell'in yazdığı karşılama ve prompt gürültüsü arasından işaretçiler arasındaki PATH'i çıkarır.
    static func parse(_ output: String) -> String? {
        guard let begin = output.range(of: beginMarker),
              let end = output.range(of: endMarker, range: begin.upperBound..<output.endIndex) else { return nil }
        let path = String(output[begin.upperBound..<end.lowerBound])
        return path.isEmpty ? nil : path
    }

    public static func capture(shell: String, timeout: Double) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", #"printf '%s%s%s' "\#(beginMarker)" "$PATH" "\#(endMarker)""#]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return parse(String(decoding: data, as: UTF8.self))
    }
}
