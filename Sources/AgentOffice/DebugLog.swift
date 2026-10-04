import Foundation

/// `AGENT_OFFICE_DEBUG=1` ile tıklama ve odak olaylarını
/// `~/Library/Application Support/AgentOffice/debug.log` dosyasına yazar. Elle yapılan kabul testlerinde
/// neyin olup neyin olmadığını görmek için.
enum DebugLog {
    static let isEnabled = ProcessInfo.processInfo.environment["AGENT_OFFICE_DEBUG"] == "1"
    private static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AgentOffice/debug.log")

    static func write(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line = "\(ISO8601DateFormatter().string(from: .now)) \(message())\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
