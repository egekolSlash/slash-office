import Darwin

/// Telefonun Mac'e hangi ağdan ulaşacağı (spec §3). Özel ağ ve tünel modları aşama 6'da.
public enum RemoteMode: String, CaseIterable, Sendable {
    case tailscale, localNetwork
}

public struct NetInterface: Equatable, Sendable {
    public let name: String
    public let address: String

    public init(name: String, address: String) {
        self.name = name
        self.address = address
    }
}

public enum RemoteInterfaces {
    /// Açık, loopback olmayan IPv4 arayüzleri.
    public static func current() -> [NetInterface] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var result: [NetInterface] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  entry.ifa_flags & UInt32(IFF_UP) != 0, entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            result.append(NetInterface(name: String(cString: entry.ifa_name), address: text))
        }
        return result
    }

    static func octets(_ address: String) -> [UInt8]? {
        let parts = address.split(separator: ".")
        guard parts.count == 4 else { return nil }
        let values = parts.compactMap { UInt8($0) }
        return values.count == 4 ? values : nil
    }

    /// Tailscale adresleri 100.64.0.0/10 (CGNAT) aralığında.
    public static func isTailscale(_ address: String) -> Bool {
        guard let o = octets(address) else { return false }
        return o[0] == 100 && (64...127).contains(o[1])
    }

    public static func isPrivateLAN(_ address: String) -> Bool {
        guard let o = octets(address) else { return false }
        return o[0] == 10 || (o[0] == 172 && (16...31).contains(o[1])) || (o[0] == 192 && o[1] == 168)
    }

    /// Moda uyan ilk arayüz; yoksa nil (sunucu açılmaz, ayarlar nedenini söyler).
    public static func bindAddress(mode: RemoteMode, interfaces: [NetInterface]) -> NetInterface? {
        switch mode {
        case .tailscale: interfaces.first { isTailscale($0.address) }
        case .localNetwork: interfaces.first { $0.name.hasPrefix("en") && isPrivateLAN($0.address) }
        }
    }
}
