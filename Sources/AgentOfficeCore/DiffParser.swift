public struct DiffLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case added, removed, context }
    public var kind: Kind
    public var text: String
}

public struct DiffHunk: Equatable, Sendable {
    public var header: String
    public var lines: [DiffLine]
}

public struct FileDiff: Equatable, Sendable, Identifiable {
    public enum Change: Equatable, Sendable { case modified, added, deleted, renamed(from: String) }
    public var path: String
    public var change: Change
    public var isBinary: Bool
    public var hunks: [DiffHunk]
    public var additions: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .added }.count } }
    public var deletions: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .removed }.count } }
    public var id: String { path }
}

/// `git diff` çıktısını (unified diff) dosya, hunk ve satırlara ayırır.
public enum DiffParser {
    public static func parse(_ patch: String) -> [FileDiff] {
        var files: [FileDiff] = []
        var current: FileDiff?
        var hunk: DiffHunk?

        func flushHunk() {
            if let finished = hunk { current?.hunks.append(finished) }
            hunk = nil
        }
        func flushFile() {
            flushHunk()
            if let finished = current { files.append(finished) }
            current = nil
        }

        for line in patch.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("diff --git ") {
                flushFile()
                current = FileDiff(path: pathFromHeader(String(line.dropFirst("diff --git ".count))),
                                   change: .modified, isBinary: false, hunks: [])
                continue
            }
            guard current != nil else { continue }
            if hunk != nil {
                switch line.first {
                case "+": hunk?.lines.append(DiffLine(kind: .added, text: String(line.dropFirst()))); continue
                case "-": hunk?.lines.append(DiffLine(kind: .removed, text: String(line.dropFirst()))); continue
                case " ": hunk?.lines.append(DiffLine(kind: .context, text: String(line.dropFirst()))); continue
                case "\\": continue // "\ No newline at end of file"
                default: break
                }
            }
            if line.hasPrefix("@@") {
                flushHunk()
                hunk = DiffHunk(header: line, lines: [])
            } else if line.hasPrefix("new file mode") {
                current?.change = .added
            } else if line.hasPrefix("deleted file mode") {
                current?.change = .deleted
            } else if line.hasPrefix("rename from ") {
                current?.change = .renamed(from: unquote(String(line.dropFirst("rename from ".count))))
            } else if line.hasPrefix("rename to ") {
                current?.path = unquote(String(line.dropFirst("rename to ".count)))
            } else if line.hasPrefix("Binary files ") {
                current?.isBinary = true
            } else if line.hasPrefix("+++ "), let path = strippedPath(line.dropFirst(4), prefix: "b/") {
                current?.path = path
            } else if line.hasPrefix("--- "), current?.change == .deleted, let path = strippedPath(line.dropFirst(4), prefix: "a/") {
                current?.path = path
            }
        }
        flushFile()
        return files
    }

    /// `+++ b/yol` ya da `--- a/yol` satırındaki yol; `/dev/null` ise nil.
    private static func strippedPath(_ raw: Substring, prefix: String) -> String? {
        var value = unquote(String(raw))
        if value.hasSuffix("\t") { value.removeLast() }
        guard value != "/dev/null" else { return nil }
        return value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : value
    }

    /// `a/P b/P` ya da `"a/P" "b/P"` başlığından yol. Boşluklu yollarda iki yarı eşit uzunluktadır.
    private static func pathFromHeader(_ rest: String) -> String {
        if rest.hasPrefix("\""), let closing = rest.dropFirst().firstIndex(of: "\"") {
            let first = unquote(String(rest[rest.startIndex...closing]))
            return first.hasPrefix("a/") ? String(first.dropFirst(2)) : first
        }
        let length = (rest.count - 5) / 2
        if length > 0, rest.hasPrefix("a/") {
            return String(rest.dropFirst(2).prefix(length))
        }
        return rest
    }

    /// Git'in C tarzı tırnaklı yollarını (`"a/Klas\303\266r"`) çözer; tırnaksızsa olduğu gibi döner.
    static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        var bytes: [UInt8] = []
        var iterator = Array(value.utf8.dropFirst().dropLast()).makeIterator()
        while let byte = iterator.next() {
            guard byte == UInt8(ascii: "\\"), let next = iterator.next() else { bytes.append(byte); continue }
            switch next {
            case UInt8(ascii: "n"): bytes.append(10)
            case UInt8(ascii: "t"): bytes.append(9)
            case UInt8(ascii: "0")...UInt8(ascii: "7"):
                var octal = Int(next - UInt8(ascii: "0"))
                for _ in 0..<2 {
                    guard let digit = iterator.next() else { break }
                    octal = octal * 8 + Int(digit - UInt8(ascii: "0"))
                }
                bytes.append(UInt8(truncatingIfNeeded: octal))
            default: bytes.append(next)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
