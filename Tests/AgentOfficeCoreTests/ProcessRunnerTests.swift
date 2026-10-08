import Foundation
import Testing
@testable import AgentOfficeCore

/// Kısa komutlar (`claude --version`, `claude agents --json`): çıktı, zaman aşımı ve stdout'u açık tutan torun süreç.
@Suite struct ProcessRunnerTests {
    @Test func capturesOutputAndStatus() {
        let result = ProcessRunner.run("/bin/sh", ["-c", "echo 2.1.294 '(Claude Code)'; exit 0"], timeout: 3)
        #expect(result?.status == 0)
        #expect(result?.output == "2.1.294 (Claude Code)\n")
    }

    @Test func usesTheGivenEnvironment() {
        let result = ProcessRunner.run("/bin/sh", ["-c", "echo $PATH"], environment: ["PATH": "/custom/bin:/usr/bin"], timeout: 3)
        #expect(result?.output == "/custom/bin:/usr/bin\n")
    }

    @Test func timesOut() {
        let start = Date()
        let result = ProcessRunner.run("/bin/sleep", ["10"], timeout: 0.5)
        #expect(Date().timeIntervalSince(start) < 3)
        #expect(result?.status != 0)
    }

    /// Arka planda kalan bir torun stdout'u açık tutsa da beklemez (eskiden okuma sonsuza kadar sürüyordu).
    @Test func grandchildHoldingStdoutDoesNotBlock() {
        let start = Date()
        let result = ProcessRunner.run("/bin/sh", ["-c", "sleep 10 & echo hi"], timeout: 3)
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(result?.output == "hi\n")
    }

    @Test func missingExecutableIsNil() {
        #expect(ProcessRunner.run("/nonexistent/tool", [], timeout: 1) == nil)
    }
}
