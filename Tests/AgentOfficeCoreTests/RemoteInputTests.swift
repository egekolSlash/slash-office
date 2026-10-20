import Testing
@testable import AgentOfficeCore

@Suite struct RemoteInputTests {
    @Test func wrapsInBracketedPaste() {
        #expect(RemoteInput.paste("Testleri çalıştır 🚀", bracketedPaste: true) == "\u{1b}[200~Testleri çalıştır 🚀\u{1b}[201~")
    }

    @Test func keepsLinesAndNormalizesCRLF() {
        #expect(RemoteInput.paste("bir\r\niki\nüç", bracketedPaste: true) == "\u{1b}[200~bir\niki\nüç\u{1b}[201~")
    }

    @Test func escapeCannotLeavePaste() {
        let attack = "a\u{1b}[201~\r/exit\r\u{7}\u{9b}b"
        #expect(RemoteInput.paste(attack, bracketedPaste: true) == "\u{1b}[200~a[201~/exitb\u{1b}[201~")
    }

    @Test func withoutBracketedPasteNewlinesBecomeSpaces() {
        #expect(RemoteInput.paste("bir\niki", bracketedPaste: false) == "bir iki")
    }

    @Test func emptyOrHugeIsRefused() {
        #expect(RemoteInput.paste("  \n ", bracketedPaste: true) == nil)
        #expect(RemoteInput.paste(String(repeating: "a", count: RemoteInput.maxTextLength + 1), bracketedPaste: true) == nil)
    }
}
