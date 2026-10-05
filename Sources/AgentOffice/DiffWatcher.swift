import AgentOfficeCore
import Foundation
import Observation

/// Değişiklikler panelinin kapsamı.
enum ChangesScope: Hashable, CaseIterable {
    /// Commit edilmemiş her şey (hazırlanmış + hazırlanmamış + yeni dosyalar). Commit edilince listeden düşer.
    case uncommitted
    /// Kullanıcının son isteğinden (shell'de son komuttan) beri olanlar.
    case lastTurn
    /// Oturum açıldığından beri olanlar (ajanın commit'leri dahil).
    case session
}

struct ChangeGroup: Equatable, Identifiable {
    var title: String
    var files: [FileDiff]
    var id: String { title }
}

enum DiffState: Equatable {
    case loading
    case ready(groups: [ChangeGroup], branch: String?)
    /// Git deposu değil: dokunulan dosyalar gösterilir.
    case noRepository
    /// Bu kapsam için başlangıç noktası yok (ör. henüz bir istek gönderilmedi).
    case unavailable(String)
}

/// Oturumların diff'ini arka planda hesaplar. Art arda gelen olaylarda `git` her seferinde çalışmasın diye
/// istekler 500 ms birleştirilir; aynı oturum için bekleyen önceki istek iptal edilir.
@MainActor
@Observable
final class DiffWatcher {
    private(set) var states: [String: DiffState] = [:]
    @ObservationIgnored private var pending: [String: Task<Void, Never>] = [:]

    /// Bu boyutun üstündeki diff'lerde satırlar atılır, sadece dosya listesi kalır.
    nonisolated static let maxPatchBytes = 2_000_000

    static func key(_ id: String, _ scope: ChangesScope) -> String { "\(id)|\(scope)" }

    func state(_ id: String, _ scope: ChangesScope) -> DiffState? { states[Self.key(id, scope)] }

    func refresh(id: String, scope: ChangesScope, cwd: String, baseline: String?, turnTree: String?,
                 delay: Duration = .milliseconds(500)) {
        let key = Self.key(id, scope)
        pending[key]?.cancel()
        if states[key] == nil { states[key] = .loading }
        pending[key] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .utility) {
                DiffWatcher.compute(scope: scope, cwd: cwd, baseline: baseline, turnTree: turnTree)
            }.value
            guard !Task.isCancelled else { return }
            DebugLog.write("diff \(key): \(result.summary)")
            self?.states[key] = result
        }
    }

    /// Odakta olmayan oturumun diff'i eskidi: bir sonraki odakta yeniden hesaplanır.
    func markStale(_ id: String) {
        for scope in ChangesScope.allCases {
            let key = Self.key(id, scope)
            pending[key]?.cancel()
            pending[key] = nil
            states[key] = nil
        }
    }

    func forget(_ id: String) { markStale(id) }

    nonisolated static func compute(scope: ChangesScope, cwd: String, baseline: String?, turnTree: String?) -> DiffState {
        let workspace = GitWorkspace(directory: cwd)
        guard workspace.isRepository else { return .noRepository }
        let branch = workspace.branch()
        switch scope {
        case .uncommitted:
            let groups = [ChangeGroup(title: "Hazırlanmış", files: parse(workspace.diff(.staged))),
                          ChangeGroup(title: "Değişiklikler", files: parse(workspace.diff(.unstaged)))]
            return .ready(groups: groups.filter { !$0.files.isEmpty }, branch: branch)
        case .lastTurn:
            guard let turnTree else { return .unavailable("Henüz bir istek gönderilmedi. İlk istekten sonra o turda değişenler burada görünecek.") }
            return .ready(groups: [ChangeGroup(title: "Son tur", files: parse(workspace.diff(.since(tree: turnTree))))]
                .filter { !$0.files.isEmpty }, branch: branch)
        case .session:
            guard let base = baseline else { return .unavailable("Bu oturumun başlangıç noktası bilinmiyor (git deposu açılmadan önce başlamış).") }
            return .ready(groups: [ChangeGroup(title: "Oturum boyunca", files: parse(workspace.diff(since: base)))]
                .filter { !$0.files.isEmpty }, branch: branch)
        }
    }

    nonisolated private static func parse(_ patch: String) -> [FileDiff] {
        let files = DiffParser.parse(patch)
        guard patch.utf8.count > maxPatchBytes else { return files }
        return files.map { var file = $0; file.hunks = []; return file }
    }
}

private extension DiffState {
    var summary: String {
        switch self {
        case .loading: "loading"
        case .noRepository: "no repository"
        case .unavailable(let reason): "unavailable: \(reason)"
        case .ready(let groups, let branch): "\(groups.map { "\($0.title):\($0.files.count)" }) on \(branch ?? "-")"
        }
    }
}
