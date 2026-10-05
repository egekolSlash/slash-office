import Foundation

public enum DiffScope: Equatable, Sendable {
    /// Hazırlanmış (index'teki) değişiklikler.
    case staged
    /// Çalışma alanındaki hazırlanmamış değişiklikler ve izlenmeyen dosyalar.
    case unstaged
    /// Bir çalışma alanı fotoğrafından (tree) bu yana olan her şey.
    case since(tree: String)
}

public struct StatusEntry: Equatable, Sendable {
    public enum Change: Equatable, Sendable { case modified, added, deleted, renamed, untracked, conflicted }
    public var path: String
    public var originalPath: String?
    public var staged: Change?
    public var unstaged: Change?
}

/// Bir oturum klasöründeki git deposuna `git` CLI üzerinden bakar. Ana thread'de çağrılmamalı (diff hariç
/// `head`/`branch` hızlıdır ama yine de süreç başlatır).
public struct GitWorkspace: Sendable {
    public let directory: String
    public let gitPath: String

    public init(directory: String, gitPath: String = "/usr/bin/git") {
        self.directory = directory
        self.gitPath = gitPath
    }

    public var isRepository: Bool {
        run(["rev-parse", "--is-inside-work-tree"]).status == 0
    }

    /// Deponun ortak `.git` klasörü (worktree'lerde ana deponunki); depo değilse nil.
    public func commonDirectory() -> String? {
        let result = run(["rev-parse", "--path-format=absolute", "--git-common-dir"])
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.status == 0 && !path.isEmpty ? path : nil
    }

    /// `git status --porcelain=v2 -z`: her dosya için hazırlanmış ve hazırlanmamış durum.
    public func status() -> [StatusEntry] {
        let result = run(["status", "--porcelain=v2", "-z", "--untracked-files=all"])
        guard result.status == 0 else { return [] }
        var entries: [StatusEntry] = []
        var fields = result.output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init).makeIterator()
        while let record = fields.next() {
            guard let kind = record.first else { continue }
            switch kind {
            case "1", "2":
                // "1 XY sub mH mI mW hH hI path" ya da "2 XY ... X<score> path" + ayrı alanda eski yol
                let parts = record.split(separator: " ", maxSplits: kind == "1" ? 8 : 9, omittingEmptySubsequences: false)
                guard parts.count >= (kind == "1" ? 9 : 10) else { continue }
                let xy = Array(parts[1])
                let path = String(parts[kind == "1" ? 8 : 9])
                let original = kind == "2" ? fields.next() : nil
                entries.append(StatusEntry(path: path, originalPath: original,
                                           staged: Self.change(xy[0]), unstaged: Self.change(xy[1])))
            case "u":
                let parts = record.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                if let path = parts.last {
                    entries.append(StatusEntry(path: String(path), originalPath: nil, staged: .conflicted, unstaged: .conflicted))
                }
            case "?":
                entries.append(StatusEntry(path: String(record.dropFirst(2)), originalPath: nil, staged: nil, unstaged: .untracked))
            default:
                continue
            }
        }
        return entries
    }

    private static func change(_ code: Character) -> StatusEntry.Change? {
        switch code {
        case "M", "T": .modified
        case "A": .added
        case "D": .deleted
        case "R", "C": .renamed
        case "U": .conflicted
        default: nil
        }
    }

    public func diff(_ scope: DiffScope) -> String {
        switch scope {
        case .staged:
            return run(["diff", "--cached", "--no-color", "--no-ext-diff"]).output
        case .unstaged:
            return run(["diff", "--no-color", "--no-ext-diff"]).output + untrackedDiff()
        case .since(let tree):
            guard let current = snapshotTree() else { return "" }
            return run(["diff", "--no-color", "--no-ext-diff", tree, current]).output
        }
    }

    /// Çalışma alanının o anki halini (izlenmeyen dosyalar dahil, .gitignore hariç) bir tree nesnesi olarak saklar.
    /// Kullanıcının index'i kopyalanıp geçici index'le çalışılır: staged durum değişmez, sadece değişen dosyalar okunur.
    public func snapshotTree() -> String? {
        let indexPath = run(["rev-parse", "--path-format=absolute", "--git-path", "index"]).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !indexPath.isEmpty, isRepository else { return nil }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("agentoffice-index-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        if FileManager.default.fileExists(atPath: indexPath) {
            try? FileManager.default.copyItem(atPath: indexPath, toPath: temporary.path)
        }
        let environment = ["GIT_INDEX_FILE": temporary.path]
        guard run(["add", "-A"], environment: environment).status == 0 else { return nil }
        let tree = run(["write-tree"], environment: environment)
        let value = tree.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return tree.status == 0 && !value.isEmpty ? value : nil
    }

    private func untrackedDiff() -> String {
        let untracked = run(["ls-files", "--others", "--exclude-standard", "-z"]).output
            .split(separator: "\0").map(String.init)
        // --no-index fark olduğunda 1 ile çıkar; bu bir hata değil.
        return untracked.map { run(["diff", "--no-index", "--no-color", "--no-ext-diff", "--", "/dev/null", $0]).output }.joined()
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
        run(["diff", "--no-color", "--no-ext-diff", baseline]).output + untrackedDiff()
    }

    private func run(_ arguments: [String], environment extra: [String: String] = [:]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["-C", directory, "-c", "core.quotePath=false"] + arguments
        process.environment = ["GIT_OPTIONAL_LOCKS": "0", "LC_ALL": "C", "PATH": "/usr/bin:/bin",
                               "HOME": NSHomeDirectory()].merging(extra) { $1 }
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
