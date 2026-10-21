import Foundation

/// ⌘-tıklanan yolu bulmak için denenecek metinler. SwiftTerm'in örtük link eşleşmesi (Ghostty düzeni) boşluklu
/// yolları ve alt satıra kaymış metni de kabul ettiği için yolun ardındaki kelimeleri, hatta alt satırı da alır.
/// Bu yüzden önce tıklanan hücrenin çevresine bakılır: aynı biçimdeki (Claude'un kod/yol rengi) kesintisiz metin,
/// sonra boşlukla ayrılmış kelime; en son SwiftTerm'in verdiği metnin baştan kısaltılmış halleri.
public enum TerminalLink {
    /// `cells`: tıklanan satırın hücreleri (karakter ve biçim), `column`: tıklanan hücre.
    public static func candidates<Style: Equatable>(cells: [(character: Character, style: Style)], column: Int, link: String) -> [String] {
        var raw: [String] = []
        if cells.indices.contains(column), !cells[column].character.isWhitespace {
            let style = cells[column].style
            let word = run(in: cells, around: column) { !$0.character.isWhitespace }
            let styledWord = run(in: cells, around: column) { !$0.character.isWhitespace && $0.style == style }
            let styledRun = run(in: cells, around: column) { $0.style == style }
            raw += [styledWord, word, styledRun.trimmingCharacters(in: .whitespaces)]
        }
        let words = link.split(whereSeparator: \.isWhitespace).map(String.init)
        // Boşluklu yol ("Kaynak Klasör/a.swift"): en uzun önekten başlanır.
        for count in stride(from: words.count, through: 1, by: -1) {
            raw.append(words.prefix(count).joined(separator: " "))
        }
        raw += words.dropFirst()
        var seen = Set<String>()
        return raw.flatMap { [$0, clean($0)] }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Yolun çevresindeki noktalama, tırnak, backtick ve parantezleri; sondaki kesme işaretli eki (`'te`, `’deki`) atar.
    public static func clean(_ text: String) -> String {
        var text = Substring(text)
        var previous = ""
        while previous != String(text) {
            previous = String(text)
            while let first = text.first, leading.contains(first) { text.removeFirst() }
            while let last = text.last, trailing.contains(last) { text.removeLast() }
            if let apostrophe = text.lastIndex(where: { $0 == "'" || $0 == "\u{2019}" }), apostrophe > text.startIndex {
                let suffix = text[text.index(after: apostrophe)...]
                if suffix.count <= 6, suffix.allSatisfy(\.isLetter) { text = text[..<apostrophe] }
            }
        }
        return String(text)
    }

    private static let leading: Set<Character> = ["\"", "'", "`", "(", "[", "{", "<", "\u{00AB}", "\u{201C}", "\u{2018}", "*"]
    private static let trailing: Set<Character> = ["\"", "'", "`", ")", "]", "}", ">", "\u{00BB}", "\u{201D}", "\u{2019}",
                                                   ".", ",", ";", ":", "!", "?", "*"]

    private static func run<Style>(in cells: [(character: Character, style: Style)], around column: Int,
                                   while matches: ((character: Character, style: Style)) -> Bool) -> String {
        guard matches(cells[column]) else { return "" }
        var start = column, end = column
        while start > 0, matches(cells[start - 1]) { start -= 1 }
        while end + 1 < cells.count, matches(cells[end + 1]) { end += 1 }
        return String(cells[start...end].map(\.character))
    }
}

extension FileKind {
    /// Sırayla denenen metinlerden var olan ilk dosya.
    public static func resolve(firstOf candidates: [String], relativeTo directory: String?,
                               fileManager: FileManager = .default) -> URL? {
        for candidate in candidates {
            if let url = resolve(candidate, relativeTo: directory, fileManager: fileManager) { return url }
        }
        return nil
    }
}
