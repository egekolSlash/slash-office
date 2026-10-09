import AgentOfficeCore
import Foundation

/// Çalışan ya da bekleyen Claude oturumunun kayıt dosyasını izler: Esc ile kesilen turda hook gelmez, kesinti
/// yalnızca kayda yazılır (`TranscriptInterrupt`). Dosya değişince (en çok saniyede bir) sonu okunur. Oturum boşta
/// ya da kapalıyken izleme yok.
@MainActor
final class TranscriptWatcher {
    var onInterrupt: ((String) -> Void)?

    private struct Watch {
        let path: String
        let source: DispatchSourceFileSystemObject
        var checkScheduled = false
    }
    private var watches: [String: Watch] = [:]
    static let minimumInterval: Duration = .seconds(1)

    /// İzlenecekse yolu verir; `nil` izlemeyi bırakır.
    func watch(_ id: String, path: String?) {
        if let current = watches[id], current.path == path { return }
        stop(id)
        guard let path else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed(id) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watches[id] = Watch(path: path, source: source)
    }

    func stop(_ id: String) {
        watches.removeValue(forKey: id)?.source.cancel()
    }

    private func changed(_ id: String) {
        guard var watch = watches[id], !watch.checkScheduled else { return }
        watch.checkScheduled = true
        watches[id] = watch
        let path = watch.path
        Task { [weak self] in
            // Kesinti satırı ve ardından gelen kayıtlar birlikte yazılsın.
            try? await Task.sleep(for: .milliseconds(300))
            let interrupted = await Task.detached(priority: .utility) {
                TranscriptInterrupt.endsWithInterrupt(in: URL(fileURLWithPath: path))
            }.value
            try? await Task.sleep(for: Self.minimumInterval - .milliseconds(300))
            guard let self, self.watches[id]?.path == path else { return }
            self.watches[id]?.checkScheduled = false
            if interrupted { self.onInterrupt?(id) }
        }
    }
}
