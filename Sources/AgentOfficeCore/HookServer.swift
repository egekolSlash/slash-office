import Darwin
import Foundation

public enum HookServerError: Error {
    case pathTooLong(String)
    case socket(Int32)
    case bind(Int32)
    case listen(Int32)
}

/// Unix socket üzerinden satır satır HookEnvelope alır.
/// Bağlantılar tek bir seri kuyrukta kabul sırasıyla işlenir; böylece bir oturumun olayları sırasını korur.
public final class HookServer: @unchecked Sendable {
    public let socketPath: String
    private let onEnvelope: @Sendable (HookEnvelope) -> Void
    private let queue = DispatchQueue(label: "agentoffice.hookserver")
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    public init(socketPath: String, onEnvelope: @escaping @Sendable (HookEnvelope) -> Void) {
        self.socketPath = socketPath
        self.onEnvelope = onEnvelope
    }

    public func start() throws {
        guard let address = UnixSocket.address(socketPath) else { throw HookServerError.pathTooLong(socketPath) }
        unlink(socketPath) // çökmüş bir önceki çalıştırmadan kalan dosya
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HookServerError.socket(errno) }
        guard UnixSocket.withSockaddr(address, { bind(fd, $0, $1) }) == 0 else {
            let error = errno
            close(fd)
            throw HookServerError.bind(error)
        }
        chmod(socketPath, 0o600)
        guard listen(fd, 64) == 0 else {
            let error = errno
            close(fd)
            throw HookServerError.listen(error)
        }
        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptOne() }
        source.setCancelHandler { close(fd) }
        acceptSource = source
        source.resume()
    }

    public func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        listenFD = -1
        unlink(socketPath)
    }

    deinit { stop() }

    private func acceptOne() {
        let client = accept(listenFD, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }
        UnixSocket.disableSigpipe(client)
        UnixSocket.setTimeout(client, option: SO_RCVTIMEO, seconds: 2)
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(client, &chunk, chunk.count)
            if count <= 0 { break }
            data.append(contentsOf: chunk[0..<count])
        }
        let decoder = JSONDecoder()
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            if let envelope = try? decoder.decode(HookEnvelope.self, from: Data(line)) {
                onEnvelope(envelope)
            }
        }
    }
}
