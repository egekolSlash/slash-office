import Testing
@testable import AgentOfficeCore

/// Özelleştirme önizlemesi: köylü sırayla döngü ve tek seferlik hareketler yapar; sıra baştan tekrarlar.
@Suite struct PreviewClipsTests {
    @Test func cyclesThroughTheSequence() {
        let first = PreviewClips.sequence[0], second = PreviewClips.sequence[1]
        #expect(PreviewClips.clip(at: 0) == first)
        #expect(PreviewClips.clip(at: PreviewClips.span(of: first) + 0.01) == second)
        #expect(PreviewClips.clip(at: PreviewClips.period + 0.01) == first)
        #expect(PreviewClips.sequence.allSatisfy { PreviewClips.span(of: $0) > 0.5 })
        #expect(Set(PreviewClips.sequence).isSuperset(of: [.wave, .cheer, .lookAround]))
        #expect(!PreviewClips.sequence.contains { $0.seated })
    }

    /// Döngüler iki tur, tek seferlikler bir kez oynar.
    @Test func spans() {
        #expect(abs(PreviewClips.span(of: .wave) - AvatarClip.wave.duration * 2) < 1e-9)
        #expect(abs(PreviewClips.span(of: .cheer) - AvatarClip.cheer.duration) < 1e-9)
    }
}
