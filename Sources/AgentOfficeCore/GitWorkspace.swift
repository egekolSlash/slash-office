import Foundation

/// Bir oturum klasöründeki git deposuna `git` CLI üzerinden bakar. Ana thread'de çağrılmamalı (diff hariç
/// `head`/`branch` hızlıdır ama yine de süreç başlatır).
public struct GitWorkspace: Sendable {
    public let directory: String
    public let gitPath: String

    public init(directory: String, gitPath: String = "/usr/bin/git") {
        self.directory = directory
        self.gitPath = gitPath
    }

    /// Depo değilse ya da henüz commit yoksa nil.
    public func head() -> String? {
        let result = run(["rev-parse", "--verify", "-q", "HEAD"])
        guard result.status == 0 else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public func branch() -> String? {
        let result = run(["rev-parse", "--abbrev-ref", "HEAD"])
        guard result.status == 0 else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Baseline'dan bu yana çalışma alanındaki değişiklikler (commit edilenler dahil) ve izlenmeyen dosyalar.
    public func diff(since baseline: String) -> String {
        var patch = run(["diff", "--no-color", "--no-ext-diff", baseline]).output
        let untracked = run(["ls-files", "--others", "--exclude-standard", "-z"]).output
            .split(separator: "\0").map(String.init)
        for file in untracked {
            // --no-index fark olduğunda 1 ile çıkar; bu bir hata değil.
            patch += run(["diff", "--no-index", "--no-color", "--no-ext-diff", "--", "/dev/null", file]).output
        }
        return patch
    }

    private func run(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["-C", directory, "-c", "core.quotePath=false"] + arguments
        process.environment = ["GIT_OPTIONAL_LOCKS": "0", "LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, "") }
        // Büyük çıktı pipe'ı doldurup süreci bekletmesin diye önce oku, sonra bekle.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
