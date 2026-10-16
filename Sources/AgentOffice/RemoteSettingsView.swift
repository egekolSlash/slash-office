import AgentOfficeCore
import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Ayarlar › Telefondan erişim (spec §4): aç/kapa, ağ, adres, eşleştirme QR'ı, eşleşmiş cihazlar.
struct RemoteSettingsSection: View {
    @Bindable var remote: RemoteBridge

    var body: some View {
        Toggle("Phone access", isOn: $remote.enabled)
        Text("Follow your sessions from your phone, answer and write back. A paired phone can make Claude run anything on this Mac, so pair only your own devices.")
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if remote.enabled {
            Picker("Network", selection: $remote.mode) {
                Text(verbatim: "Tailscale").tag(RemoteMode.tailscale)
                Text("Local network").tag(RemoteMode.localNetwork)
            }
            .pickerStyle(.segmented)
            if remote.mode == .localNetwork {
                Text("On the local network, traffic is not encrypted. Use it only on networks you trust.")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            status
            if case .running = remote.status { pairing }
            ForEach(remote.devices) { device in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: device.name)
                        if let lastSeen = device.lastSeen {
                            Text("Last seen \(lastSeen.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Not connected yet").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Revoke") { remote.revoke(device) }
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch remote.status {
        case .off:
            EmptyView()
        case .starting:
            Text("Starting…").font(.callout).foregroundStyle(.secondary)
        case .running(let url):
            LabeledContent("Address") { Text(verbatim: url).textSelection(.enabled) }
        case .noInterface:
            if remote.mode == .tailscale {
                Text("Tailscale is not connected on this Mac. Open Tailscale and sign in; the address appears here by itself.")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("This Mac is not on a local network.").font(.callout).foregroundStyle(.orange)
            }
        case .failed(let message):
            Text("Could not start: \(message)").font(.callout).foregroundStyle(.red)
        }
    }

    @ViewBuilder private var pairing: some View {
        if let url = remote.pairingURL, let image = QRCode.image(for: url) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 140, height: 140)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scan with your phone's camera.").font(.callout)
                    Text(verbatim: remote.pairingCode ?? "").font(.system(.title2, design: .monospaced))
                    Text("The code works once, for 2 minutes.").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            Button("Pair a Phone…") { remote.newPairingCode() }
        }
    }
}

enum QRCode {
    static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
