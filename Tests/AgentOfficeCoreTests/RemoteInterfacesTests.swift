import Testing
@testable import AgentOfficeCore

@Suite struct RemoteInterfacesTests {
    @Test func tailscaleRangeIs100_64Slash10() {
        #expect(RemoteInterfaces.isTailscale("100.64.0.1"))
        #expect(RemoteInterfaces.isTailscale("100.127.255.254"))
        #expect(!RemoteInterfaces.isTailscale("100.63.255.255"))
        #expect(!RemoteInterfaces.isTailscale("100.128.0.1"))
        #expect(!RemoteInterfaces.isTailscale("192.168.1.10"))
        #expect(!RemoteInterfaces.isTailscale("fe80::1"))
    }

    @Test func privateLANRanges() {
        #expect(RemoteInterfaces.isPrivateLAN("10.0.0.5"))
        #expect(RemoteInterfaces.isPrivateLAN("172.16.0.1") && RemoteInterfaces.isPrivateLAN("172.31.255.1"))
        #expect(!RemoteInterfaces.isPrivateLAN("172.32.0.1"))
        #expect(RemoteInterfaces.isPrivateLAN("192.168.1.20"))
        #expect(!RemoteInterfaces.isPrivateLAN("8.8.8.8"))
        #expect(!RemoteInterfaces.isPrivateLAN("100.70.1.2"))
    }

    let interfaces = [NetInterface(name: "en0", address: "192.168.1.20"),
                      NetInterface(name: "utun4", address: "100.101.102.103"),
                      NetInterface(name: "en5", address: "203.0.113.9")]

    @Test func picksTheAddressForTheMode() {
        #expect(RemoteInterfaces.bindAddress(mode: .tailscale, interfaces: interfaces)?.address == "100.101.102.103")
        #expect(RemoteInterfaces.bindAddress(mode: .localNetwork, interfaces: interfaces)?.address == "192.168.1.20")
    }

    @Test func nothingToBindWhenTheNetworkIsMissing() {
        let lanOnly = [NetInterface(name: "en0", address: "192.168.1.20")]
        #expect(RemoteInterfaces.bindAddress(mode: .tailscale, interfaces: lanOnly) == nil)
        let vpnOnly = [NetInterface(name: "utun4", address: "100.101.102.103")]
        #expect(RemoteInterfaces.bindAddress(mode: .localNetwork, interfaces: vpnOnly) == nil)
    }

    @Test func currentListsNoLoopback() {
        #expect(!RemoteInterfaces.current().contains { $0.address == "127.0.0.1" })
    }
}
