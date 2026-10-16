import AgentOfficeCore
import Foundation
import Observation

/// Uzaktan erişimin uygulama tarafı (spec §2): ayarlara göre sunucuyu seçilen adreste açar ya da kapatır, oturum
/// listesini ve transkript değişikliklerini telefona yayınlar, telefondan gelen komutları modele iletir.
@MainActor
@Observable
final class RemoteBridge {
    enum Status: Equatable {
        case off, starting, running(url: String), noInterface, failed(String)
    }

    static let enabledKey = "remoteEnabled"
    static let modeKey = "remoteMode"
    static let portKey = "remotePort"
    static let defaultPort: UInt16 = 47821

    private(set) var status: Status = .off
    private(set) var pairingCode: String?
    private(set) var devices: [PairedDevice] = []

    var enabled = UserDefaults.standard.bool(forKey: RemoteBridge.enabledKey) {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            apply()
        }
    }

    var mode = RemoteMode(rawValue: UserDefaults.standard.string(forKey: RemoteBridge.modeKey) ?? "") ?? .tailscale {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
            apply()
        }
    }

    /// QR'ın içeriği: kod URL'nin parçasında (#), sunucu günlüğüne ve geçmişe istek olarak gitmez.
    var pairingURL: String? {
        guard case .running(let url) = status, let pairingCode else { return nil }
        return "\(url)/#pair=\(pairingCode)"
    }

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var auth: RemoteAuth?
    @ObservationIgnored private var server: RemoteServer?
    @ObservationIgnored private var boundAddress: String?
    @ObservationIgnored private var lastSnapshot: [RemoteSession] = []
    @ObservationIgnored private var interfaceTimer: Timer?
    /// Eski bir başlatmanın geç gelen sonucu yeni durumu ezmesin.
    @ObservationIgnored private var generation = 0

    private static var staticRoot: URL? {
        let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return RemoteStatic.find(bundleResources: Bundle.main.resourceURL, repoRoot: repoRoot)
    }

    func attach(_ model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        let auth = RemoteAuth(fileURL: model.supportDirectory.appendingPathComponent("remote-devices.json"))
        auth.onChange = { [weak self] in
            Task { @MainActor in self?.devices = self?.auth?.devices ?? [] }
        }
        self.auth = auth
        devices = auth.devices
        observeSessions()
        apply()
    }

    /// Ayar ya da ağ değişince sunucuyu istenen adreste tutar; adres değiştiyse yeniden başlatır.
    func apply() {
        guard let model, let auth else { return }
        guard enabled else {
            interfaceTimer?.invalidate()
            interfaceTimer = nil
            stopServer()
            status = .off
            return
        }
        if interfaceTimer == nil {
            // Tailscale açılıp kapanınca ya da Wi-Fi değişince adres değişir.
            interfaceTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            }
        }
        guard let interface = RemoteInterfaces.bindAddress(mode: mode, interfaces: RemoteInterfaces.current()) else {
            stopServer()
            status = .noInterface
            return
        }
        guard server == nil || interface.address != boundAddress else { return }
        stopServer()
        generation += 1
        let current = generation
        let server = RemoteServer(handlers: handlers(model: model, auth: auth))
        self.server = server
        boundAddress = interface.address
        status = .starting
        let stored = UserDefaults.standard.integer(forKey: Self.portKey)
        let port = (1...65_535).contains(stored) ? UInt16(stored) : Self.defaultPort
        Task {
            do {
                let actual = try await server.start(host: interface.address, port: port)
                guard current == generation else { return }
                status = .running(url: "http://\(interface.address):\(actual)")
                DebugLog.write("remote server on \(interface.address):\(actual)")
            } catch {
                guard current == generation else { return }
                stopServer()
                status = .failed(error.localizedDescription)
            }
        }
    }

    func newPairingCode() {
        guard let auth else { return }
        let code = auth.newPairingCode()
        pairingCode = code
        Task {
            try? await Task.sleep(for: .seconds(RemoteAuth.codeLifetime))
            if pairingCode == code { pairingCode = nil }
        }
    }

    func revoke(_ device: PairedDevice) {
        if auth?.revoke(device.id) == false {
            DebugLog.write("remote revoke not saved to disk: \(device.id)")
        }
        server?.disconnect(deviceId: device.id)
        devices = auth?.devices ?? []
    }

    func transcriptChanged(_ id: String) {
        server?.broadcast(.transcriptChanged(sessionId: id))
    }

    func stop() {
        interfaceTimer?.invalidate()
        interfaceTimer = nil
        stopServer()
    }

    private func stopServer() {
        generation += 1
        server?.stop()
        server = nil
        boundAddress = nil
        lastSnapshot = []
    }

    private func snapshot() -> [RemoteSession] {
        guard let model else { return [] }
        return RemoteSnapshot.sessions(model.store.sessions, canSend: { model.canSendRemotely($0) })
    }

    /// Oturum listesindeki her değişiklik (hook, shell yoklaması, kaldırma) telefona gider; aynıysa gönderilmez.
    private func observeSessions() {
        withObservationTracking {
            _ = model?.store.sessions
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sessionsChanged()
                self?.observeSessions()
            }
        }
    }

    private func sessionsChanged() {
        guard let server else { return }
        let current = snapshot()
        guard current != lastSnapshot else { return }
        lastSnapshot = current
        server.broadcast(.sessions(current))
    }

    private func handlers(model: AppModel, auth: RemoteAuth) -> RemoteServer.Handlers {
        let routes = RemoteRoutes(
            auth: auth,
            staticRoot: Self.staticRoot,
            sessions: { [weak self] in await self?.snapshot() ?? [] },
            transcript: { [weak model] id, after in
                guard let path = await model?.remoteTranscriptPath(id) else { return nil }
                let url = URL(fileURLWithPath: path)
                if let after { return TranscriptReader.read(url: url, from: after) }
                return TranscriptReader.tail(url: url)
            })
        return RemoteServer.Handlers(
            routes: routes,
            // Zayıf: model → köprü → sunucu → handlers → model döngüsü olmasın.
            command: { [weak model] message in await model?.handleRemote(message) },
            welcome: { [weak self] in [.sessions(await self?.snapshot() ?? [])] })
    }
}
