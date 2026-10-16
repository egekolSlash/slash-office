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
            stored.append(PairedDevice(id: UUID().uuidString, name: trimmed.isEmpty ? "Phone" : String(trimmed.prefix(40)),
                                       tokenHash: Self.hash(token), pairedAt: now(), lastSeen: nil))
            save()
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

    public func revoke(_ id: String) {
        lock.withLock {
            stored.removeAll { $0.id == id }
            save()
        }
        onChange?()
    }

    private func activeCode() -> Code? {
        guard let code, code.expires > now() else { return nil }
        return code
    }

    /// Kilit içinde çağrılır.
    private func save() {
        guard let data = try? RemoteJSON.encoder().encode(stored) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        chmod(fileURL.path, 0o600)
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
