import CryptoKit
import Foundation

public struct PairedDevice: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public let tokenHash: String
    public let pairedAt: Date
    public var lastSeen: Date?
}

/// Eşleştirme kodu ve cihaz token'ları (spec §4). Token'ın kendisi saklanmaz, yalnızca SHA-256'sı.
/// Sunucu kuyruğundan ve ana aktörden çağrılır; durum kilitle korunur.
public final class RemoteAuth: @unchecked Sendable {
    public static let codeLifetime: TimeInterval = 120
    public static let maxAttempts = 5

    private struct Code {
        let value: String
        let expires: Date
        var attemptsLeft: Int
    }

    private let lock = NSLock()
    private let fileURL: URL
    private let now: @Sendable () -> Date
    private var code: Code?
    private var stored: [PairedDevice]
    /// Cihaz listesi değişti (eşleşme, iptal). Herhangi bir kuyrukta çağrılabilir.
    public var onChange: (@Sendable () -> Void)?

    public init(fileURL: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.now = now
        stored = (try? RemoteJSON.decoder().decode([PairedDevice].self, from: Data(contentsOf: fileURL))) ?? []
    }

    public var devices: [PairedDevice] { lock.withLock { stored } }

    /// Geçerli kod; süresi dolduysa ya da kullanıldıysa nil.
    public var currentCode: String? { lock.withLock { activeCode()?.value } }

    /// Yeni kod üretir, öncekini geçersiz kılar.
    @discardableResult
    public func newPairingCode() -> String {
        let value = String(format: "%06ld", Int.random(in: 0..<1_000_000))
        lock.withLock { code = Code(value: value, expires: now().addingTimeInterval(Self.codeLifetime), attemptsLeft: Self.maxAttempts) }
        return value
    }

    /// Kod doğruysa yeni cihaz kaydedilir ve token döner; yanlışsa deneme hakkı düşer, biterse kod silinir.
    /// Kayıt diske yazılamazsa cihaz geri alınır ve token verilmez.
    public func pair(code attempt: String, deviceName: String) -> String? {
        let token: String? = lock.withLock {
            guard var current = activeCode() else { return nil }
            guard attempt == current.value else {
                current.attemptsLeft -= 1
                code = current.attemptsLeft > 0 ? current : nil
                return nil
            }
            code = nil
            let token = Self.randomToken()
            let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
            let device = PairedDevice(id: UUID().uuidString, name: trimmed.isEmpty ? "Phone" : String(trimmed.prefix(40)),
                                      tokenHash: Self.hash(token), pairedAt: now(), lastSeen: nil)
            stored.append(device)
            guard save() else {
                stored.removeAll { $0.id == device.id }
                return nil
            }
            return token
        }
        if token != nil { onChange?() }
        return token
    }

    /// Token geçerliyse cihaz; son görülme bellekte güncellenir.
    public func device(forToken token: String) -> PairedDevice? {
        let hash = Self.hash(token)
        return lock.withLock {
            guard let index = stored.firstIndex(where: { $0.tokenHash == hash }) else { return nil }
            stored[index].lastSeen = now()
            return stored[index]
        }
    }

    /// Cihazı bellekten çıkarır. Diske yazılamazsa false döner (bellekte yine de çıkmıştır);
    /// bu durumda cihaz yeniden başlatmadan sonra geri gelebilir.
    @discardableResult
    public func revoke(_ id: String) -> Bool {
        let saved: Bool = lock.withLock {
            stored.removeAll { $0.id == id }
            return save()
        }
        onChange?()
        return saved
    }

    private func activeCode() -> Code? {
        guard let code, code.expires > now() else { return nil }
        return code
    }

    /// Kilit içinde çağrılır. Dosya önce 0600 izinli geçici dosyaya yazılır, sonra atomik olarak yerine taşınır;
    /// böylece hedef dosya hiçbir zaman daha gevşek izinle görünmez.
    private func save() -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let data = try RemoteJSON.encoder().encode(stored)
            let temp = directory.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
            guard FileManager.default.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                return false
            }
            guard rename(temp.path, fileURL.path) == 0 else {
                try? FileManager.default.removeItem(at: temp)
                return false
            }
            return true
        } catch {
            return false
        }
    }

    static func randomToken() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
