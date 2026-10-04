import Darwin
import Foundation

public enum HookServerError: Error {
    case pathTooLong(String)
    case socket(Int32)
    case bind(Int32)
    case listen(Int32)
    case alreadyRunning(String)
}

/// Unix socket üzerinden satır satır HookEnvelope alır.
/// Bağlantılar tek bir seri kuyrukta kabul sırasıyla işlenir; böylece bir oturumun olayları sırasını korur.
public final class HookServer: @unchecked Sendable {
    public let socketPath: String
    private let onEnvelope: @Sendable (HookEnvelope) -> Void
    private let queue = DispatchQueue(label: "agentoffice.hookserver")
    /// Çözümleme ayrı seri kuyrukta: büyük bir payload'ı çözerken yeni bağlantılar kabul edilmeye devam eder, sıra korunur.
    private let decodeQueue = DispatchQueue(label: "agentoffice.hookserver.decode")
    private let lock = NSLock()
    private var acceptSource: DispatchSourceRead?
    /// Bağlandığımız socket dosyasının kimliği; stop() sadece kendi dosyamızı siler.
    private var boundFile: (device: dev_t, inode: ino_t)?

    public init(socketPath: String, onEnvelope: @escaping @Sendable (HookEnvelope) -> Void) {
        self.socketPath = socketPath
        self.onEnvelope = onEnvelope
    }

    public func start() throws {
        guard let address = UnixSocket.address(socketPath) else { throw HookServerError.pathTooLong(socketPath) }
        // Başka bir kopya dinliyorsa onun socket'ini ele geçirme; dinleyen yoksa dosya çökmüş bir çalıştırmadan kalmıştır.
        if HookClient.canConnect(toSocket: socketPath) { throw HookServerError.alreadyRunning(socketPath) }
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HookServerError.socket(errno) }
        guard UnixSocket.withSockaddr(address, { bind(fd, $0, $1) }) == 0 else {
            let error = errno
            close(fd)
            throw HookServerError.bind(error)
        }
        chmod(socketPath, 0o600)
        var info = stat()
        let identity = stat(socketPath, &info) == 0 ? (info.st_dev, info.st_ino) : nil
        guard listen(fd, 64) == 0 else {
            let error = errno
            close(fd)
            throw HookServerError.listen(error)
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptOne(listenFD: fd) }
        source.setCancelHandler { close(fd) }
        lock.withLock {
            acceptSource = source
            boundFile = identity.map { (device: $0.0, inode: $0.1) }
        }
        source.resume()
    }

    public func stop() {
        let (source, file) = lock.withLock {
            defer { acceptSource = nil; boundFile = nil }
            return (acceptSource, boundFile)
        }
        source?.cancel()
        // Aynı yola sonradan bağlanan başka bir sunucunun dosyasını silme.
        var info = stat()
        if let file, stat(socketPath, &info) == 0, info.st_dev == file.device, info.st_ino == file.inode {
            unlink(socketPath)
        }
    }

    deinit { stop() }

    private func acceptOne(listenFD: Int32) {
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
        let onEnvelope = onEnvelope
        decodeQueue.async {
            let decoder = JSONDecoder()
            for line in data.split(separator: 0x0A) where !line.isEmpty {
                if let envelope = try? decoder.decode(HookEnvelope.self, from: Data(line)) {
                    onEnvelope(envelope)
                }
            }
        }
    }
}
