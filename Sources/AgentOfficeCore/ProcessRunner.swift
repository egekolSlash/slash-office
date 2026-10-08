import Foundation

/// Kısa bir komutu çalıştırıp çıktısını döner (`claude --version`, `claude agents --json`). Çıktı boru yerine geçici
/// dosyaya gider: arka planda kalan bir torun süreç stdout'u açık tutsa da okuma beklemez. Zaman aşımında süreç
/// sonlandırılır. Çalıştırılamazsa nil.
public enum ProcessRunner {
    public struct Result: Equatable, Sendable {
        public var status: Int32
        public var output: String
    }

    public static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil,
                           timeout: TimeInterval) -> Result? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("slash-office-\(UUID().uuidString).out")
        guard FileManager.default.createFile(atPath: file.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: file) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { try? handle.close(); return nil }
        try? handle.close()
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 1)
        }
        let output = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return Result(status: process.isRunning ? -1 : process.terminationStatus, output: output)
    }
}
