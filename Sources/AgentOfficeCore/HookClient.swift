import Darwin
import Foundation

public enum HookClient {
    /// Satırı (sonuna \n ekleyerek) socket'e yazar. Dinleyici yoksa hemen false döner.
    @discardableResult
    public static func send(_ line: Data, toSocket path: String, timeout: TimeInterval = 0.3) -> Bool {
        guard let address = UnixSocket.address(path) else { return false }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        UnixSocket.disableSigpipe(fd)
        UnixSocket.setTimeout(fd, option: SO_SNDTIMEO, seconds: timeout)
        guard UnixSocket.withSockaddr(address, { connect(fd, $0, $1) }) == 0 else { return false }
        var data = line
        data.append(0x0A)
        return data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written <= 0 { return false }
                offset += written
            }
            return true
        }
    }

    static func canConnect(toSocket path: String) -> Bool {
        guard let address = UnixSocket.address(path) else { return false }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        return UnixSocket.withSockaddr(address, { connect(fd, $0, $1) }) == 0
    }
}
