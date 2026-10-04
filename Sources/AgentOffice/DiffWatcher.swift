import AgentOfficeCore
import Foundation
import Observation

enum DiffState: Equatable {
    case loading
    case ready(files: [FileDiff], branch: String?)
    /// Git deposu değil ya da hiç commit yok: dokunulan dosyalar gösterilir.
    case noRepository
}

/// Oturumların diff'ini arka planda hesaplar. Art arda gelen olaylarda `git` her seferinde çalışmasın diye
/// istekler 500 ms birleştirilir; aynı oturum için bekleyen önceki istek iptal edilir.
@MainActor
@Observable
final class DiffWatcher {
    private(set) var states: [String: DiffState] = [:]
    @ObservationIgnored private var pending: [String: Task<Void, Never>] = [:]

    /// Dosya başına gösterilecek en fazla satır; daha büyük diff'ler kesilir.
    nonisolated static let maxLinesPerFile = 400
    /// Bu boyutun üstündeki diff'lerde satırlar atılır, sadece dosya listesi kalır.
    nonisolated static let maxPatchBytes = 2_000_000

    func refresh(id: String, cwd: String, baseline: String?, delay: Duration = .milliseconds(500)) {
        pending[id]?.cancel()
        if states[id] == nil { states[id] = .loading }
        pending[id] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .utility) { DiffWatcher.compute(cwd: cwd, baseline: baseline) }.value
            guard !Task.isCancelled else { return }
            DebugLog.write("diff \(id): \(result.summary)")
            self?.states[id] = result
        }
    }

    /// Odakta olmayan oturumun diff'i eskidi: bir sonraki odakta yeniden hesaplanır.
    func markStale(_ id: String) {
        pending[id]?.cancel()
        pending[id] = nil
        states[id] = nil
    }

    func forget(_ id: String) { markStale(id) }

    nonisolated static func compute(cwd: String, baseline: String?) -> DiffState {
        let workspace = GitWorkspace(directory: cwd)
        guard let base = baseline ?? workspace.head() else { return .noRepository }
        let patch = workspace.diff(since: base)
        var files = DiffParser.parse(patch)
        if patch.utf8.count > maxPatchBytes {
            files = files.map { var file = $0; file.hunks = []; return file }
        }
        return .ready(files: files, branch: workspace.branch())
    }
}

private extension DiffState {
    var summary: String {
        switch self {
        case .loading: "loading"
        case .noRepository: "no repository"
        case .ready(let files, let branch): "\(files.count) files on \(branch ?? "-")"
        }
    }
}
