# Telefondan Uzaktan Erişim — Aşama 1–2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Slash Office'e varsayılan olarak kapalı bir "Telefondan erişim" özelliği eklemek. Telefon (PWA), Tailscale ya da yerel ağ üzerinden Mac'e bağlanır; oturum listesini ve bir oturumun konuşmasını canlı görür, mesaj yazar ve çalışan turu durdurur.

**Architecture:** Ağdan bağımsız mantık `AgentOfficeCore`'da durur ve test edilir: protokol tipleri, eşleştirme ve token, arayüz seçimi, transkript okuma, HTTP ve WebSocket çerçeveleme, HTTP uçları, terminale gidecek metnin temizlenmesi. `RemoteServer` (Network.framework `NWListener`, elle HTTP + RFC 6455 çerçeveleme) de Core'dadır ve 127.0.0.1 üzerinde entegrasyon testleriyle sınanır. Uygulama tarafında `RemoteBridge` ayarlara göre sunucuyu açıp kapatır, `AgentStore`'u gözleyip oturum listesini yayınlar, transkript değişikliklerini haber verir ve telefondan gelen metni `AgentTerminalView.send(txt:)` ile terminale yazar. Telefon, transkriptin değiştiğini WebSocket'ten duyar ve yeni mesajları HTTP ile kendi imlecinden çeker; böylece imleç yarışı olmaz.

**Tech Stack:** Swift 6.3 (strict concurrency), Swift Testing, Network.framework, CryptoKit, CoreImage (QR), SwiftUI. Telefon tarafı bağımlılıksız düz HTML/CSS/JS.

**Spec:** `docs/superpowers/specs/2026-10-15-remote-access-design.md` (§1 kapsam, §3 modlar, §4 eşleştirme, §5 ekranlar, §6 serbest metin ve durdurma, §7 protokol, §8 aşama 1–2). Canlı doküman: https://claude.ai/code/artifact/f4b0bcea-5fd2-49ac-80ea-17c2bfac6215

**Bu planın dışında (ayrı planlar):** Aşama 3 (AskUserQuestion kartı), 4 (`PermissionRequest` hook'u ve `--wait`), 5 (`tailscale serve` + web push), 6 (özel ağ ve tünel modları). Aşama 3 ve 4'ten önce spec'teki açık sorular gerçek bir Claude oturumunda denenmeli.

## Global Constraints

- macOS 26, Swift 6.3, strict concurrency. Yeni paket bağımlılığı yok; yalnızca Network, CryptoKit, CoreImage.
- Özellik varsayılan kapalı (`UserDefaults` anahtarı `remoteEnabled`, varsayılan `false`).
- Hiçbir modda `0.0.0.0` dinlenmez; sunucu yalnızca seçilen arayüzün IPv4 adresine bağlanır. Tailscale = 100.64.0.0/10, yerel ağ = `en*` arayüzündeki özel adres (10/8, 172.16/12, 192.168/16).
- Varsayılan port 47821 (`remotePort` ile değiştirilebilir).
- Eşleştirme kodu 6 hane, 120 sn geçerli, tek kullanımlık, 5 yanlış denemede silinir. Cihaz token'ı 32 rastgele bayt (base64url). Mac yalnızca SHA-256 hex hash'ini saklar: `~/Library/Application Support/AgentOffice/remote-devices.json`, izin 0600. (Spec §4 "Keychain" diyor; hash sır olmadığı için dosya yeterli ve test edilebilir. Bu sapma bilinçli.)
- HTTP: `Authorization: Bearer <token>`. WebSocket: ilk mesaj `{"type":"auth","token":…}`; 10 sn içinde gelmezse ya da token geçersizse kapanış kodu 4401.
- Arayüz metinleri Swift kaynağında İngilizce, Türkçesi `Resources/Localizable.xcstrings`'te (`LocalizationTests` bunu zorlar; kaynakta Türkçe dize sabiti olamaz, yorumlar Türkçe olabilir). Üçlü ifade içinde metin kullanma; `if/else` ile ayrı `Text` yaz.
- Protokol spec §7'den bilinçli olarak sadeleşti: `session.updated`/`session.removed` yerine her değişiklikte tam liste (`sessions`); `transcript.appended` yerine `transcript.changed` bildirimi, mesajları telefon kendi imleciyle HTTP'den çeker. `input.requested`/`input.resolved` ve `answer.*` aşama 3–4'te eklenir.
- Hook davranışı bu planda değişmez (`agent-office-hook` tek yönlü kalır).
- PWA dış kaynak yüklemez (CDN yok); veriden gelen her şey DOM'a `textContent` ile yazılır, `innerHTML` yok.
- `docs/superpowers/` gitignore'da: plan ve spec commit edilmez.
- Komutlar worktree kökünde çalışır: `/Users/egekol/git/agent-office-remote`.

## Review Focus

1. **Telefondan gelen metinde ESC ya da `\e[201~`** varsa bracketed paste'ten kaçıp tuş gönderememeli; kontrol karakterleri atılmalı. → Task 8 testi `escapeCannotLeavePaste`.
2. **Claude'un yarım yazdığı transkript satırı** okunduğunda tüketilmemeli; imleç o satırın başında kalmalı, bir sonraki okumada mesaj gelmeli. → Task 4 testi `partialLineIsNotConsumed`.
3. **İptal edilen cihazın açık WebSocket'i** hemen kapanmalı. → Task 7 testi `revokedDeviceIsDisconnected`.
4. **Auth'tan önce gelen mesaj ya da yanlış token** bağlantıyı 4401 ile kapatmalı, hiçbir veri gönderilmemeli. → Task 7 testi `messagesBeforeAuthCloseTheSocket`.
5. **Panelde çalışmayan oturuma** (durmuş ya da arka planda) mesaj gönderilememeli: snapshot'ta `canSend == false`, komut `not_running` hatası döner. → Task 1 testi `exitedSessionCannotSend`, Task 9 adım 6.

---

### Task 1: Protokol tipleri ve oturum anlık görüntüsü

**Files:**
- Create: `Sources/AgentOfficeCore/RemoteProtocol.swift`
- Test: `Tests/AgentOfficeCoreTests/RemoteProtocolTests.swift`

**Interfaces:**
- Consumes: `AgentStore.Session`, `AgentState`, `InputReason`, `TodoItem` (mevcut).
- Produces:
  - `public struct RemoteSession: Codable, Equatable, Sendable` — alanlar `id, title: String`, `status: RemoteSession.Status`, `detail: String?`, `summary: String?`, `todos: [RemoteTodo]`, `finishedUnseen: Bool`, `canSend: Bool`. `Status`: `starting, idle, working, permission, question, exited` (String raw).
  - `public struct RemoteTodo: Codable, Equatable, Sendable { title: String; status: Status }`, `Status`: `pending, inProgress, done`.
  - `public struct RemoteMessage: Codable, Equatable, Sendable { id: String; role: Role; text: String; time: String? }`, `Role`: `user, assistant, tool`.
  - `public struct TranscriptPage: Codable, Equatable, Sendable { messages: [RemoteMessage]; cursor: UInt64 }`
  - `public enum ServerEvent: Equatable, Sendable, Encodable { case ready, sessions([RemoteSession]), transcriptChanged(sessionId: String), error(String) }` + `func jsonData() -> Data`. JSON `type`: `ready`, `sessions`, `transcript.changed`, `error` (hata alanı `code`).
  - `public enum ClientMessage: Equatable, Sendable, Decodable { case auth(token: String), sendText(sessionId: String, text: String), interrupt(sessionId: String) }`. JSON `type`: `auth`, `send.text`, `interrupt`.
  - `public enum RemoteJSON { static func encoder() -> JSONEncoder; static func decoder() -> JSONDecoder }` (ISO 8601 tarihler).
  - `public enum RemoteSnapshot { static func sessions(_ sessions: [AgentStore.Session], canSend: (String) -> Bool) -> [RemoteSession] }`. Sıra: permission, question, working, bitmiş-görülmemiş idle, idle, starting, exited; aynı sınıfta store sırası korunur.

- [ ] **Step 1: Başarısız testleri yaz**

```swift
import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct RemoteProtocolTests {
    func session(_ id: String, _ state: AgentState, unseen: Bool = false) -> AgentStore.Session {
        var s = AgentStore.Session(id: id, title: "proj-\(id)", cwd: "/p/\(id)", state: state)
        s.unseenFinish = unseen
        return s
    }

    @Test func waitingSessionsComeFirst() {
        let list = RemoteSnapshot.sessions([
            session("a", .exited), session("b", .idle), session("c", .working(tool: "Bash")),
            session("d", .waiting(.question("Renk?"))), session("e", .waiting(.permission("Bash"))),
            session("f", .idle, unseen: true), session("g", .starting),
        ], canSend: { _ in true })
        #expect(list.map(\.id) == ["e", "d", "c", "f", "b", "g", "a"])
    }

    @Test func detailCarriesToolOrQuestion() {
        let list = RemoteSnapshot.sessions([session("c", .working(tool: "Bash")), session("d", .waiting(.question("Renk?")))],
                                           canSend: { _ in true })
        #expect(list.first { $0.id == "c" }?.detail == "Bash")
        #expect(list.first { $0.id == "d" }?.status == .question)
        #expect(list.first { $0.id == "d" }?.detail == "Renk?")
    }

    @Test func exitedSessionCannotSend() {
        let list = RemoteSnapshot.sessions([session("a", .exited), session("b", .idle)], canSend: { _ in true })
        #expect(list.first { $0.id == "a" }?.canSend == false)
        #expect(list.first { $0.id == "b" }?.canSend == true)
    }

    @Test func todosMap() {
        var s = session("a", .working(tool: nil))
        s.todos = [TodoItem(title: "x", status: .inProgress), TodoItem(title: "y", status: .done)]
        let remote = RemoteSnapshot.sessions([s], canSend: { _ in false })[0]
        #expect(remote.todos == [RemoteTodo(title: "x", status: .inProgress), RemoteTodo(title: "y", status: .done)])
    }

    @Test func serverEventsCarryType() throws {
        let object = try JSONSerialization.jsonObject(with: ServerEvent.transcriptChanged(sessionId: "s1").jsonData()) as? [String: Any]
        #expect(object?["type"] as? String == "transcript.changed")
        #expect(object?["sessionId"] as? String == "s1")
        let error = try JSONSerialization.jsonObject(with: ServerEvent.error("not_running").jsonData()) as? [String: Any]
        #expect(error?["code"] as? String == "not_running")
    }

    @Test func clientMessagesDecode() throws {
        let decoder = RemoteJSON.decoder()
        #expect(try decoder.decode(ClientMessage.self, from: Data(#"{"type":"send.text","sessionId":"s","text":"merhaba"}"#.utf8))
                == .sendText(sessionId: "s", text: "merhaba"))
        #expect(try decoder.decode(ClientMessage.self, from: Data(#"{"type":"auth","token":"t"}"#.utf8)) == .auth(token: "t"))
        #expect(throws: DecodingError.self) {
            try decoder.decode(ClientMessage.self, from: Data(#"{"type":"rm -rf"}"#.utf8))
        }
    }
}
```

- [ ] **Step 2: RED gör**

Run: `swift test --filter RemoteProtocolTests`
Expected: derleme hatası (`RemoteSnapshot`, `ServerEvent` yok).

- [ ] **Step 3: Uygula**

```swift
import Foundation

/// Telefonun gördüğü oturum (spec §5): durum, bekleme nedeni, iş özeti, todo'lar.
public struct RemoteSession: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case starting, idle, working, permission, question, exited }
    public var id: String
    public var title: String
    public var status: Status
    /// Çalışırken tool adı; beklerken soru ya da izin metni.
    public var detail: String?
    public var summary: String?
    public var todos: [RemoteTodo]
    public var finishedUnseen: Bool
    /// Telefondan mesaj gönderilebilir mi (oturum bu Mac'te bir panelde çalışıyor).
    public var canSend: Bool
}

public struct RemoteTodo: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case pending, inProgress, done }
    public var title: String
    public var status: Status
}

public struct RemoteMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant, tool }
    public var id: String
    public var role: Role
    public var text: String
    public var time: String?
}

/// Transkriptten okunan mesajlar ve bir sonraki okumanın başlayacağı bayt.
public struct TranscriptPage: Codable, Equatable, Sendable {
    public var messages: [RemoteMessage]
    public var cursor: UInt64
}

/// Mac → telefon (WebSocket).
public enum ServerEvent: Equatable, Sendable {
    case ready
    case sessions([RemoteSession])
    /// Transkript değişti; telefon yeni mesajları kendi imlecinden HTTP ile çeker.
    case transcriptChanged(sessionId: String)
    /// Hata kodu (`not_running`, `invalid_text`, `bad_message`); telefon kendi dilinde gösterir.
    case error(String)
}

extension ServerEvent: Encodable {
    private enum Keys: String, CodingKey { case type, sessions, sessionId, code }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .ready:
            try container.encode("ready", forKey: .type)
        case .sessions(let list):
            try container.encode("sessions", forKey: .type)
            try container.encode(list, forKey: .sessions)
        case .transcriptChanged(let id):
            try container.encode("transcript.changed", forKey: .type)
            try container.encode(id, forKey: .sessionId)
        case .error(let code):
            try container.encode("error", forKey: .type)
            try container.encode(code, forKey: .code)
        }
    }

    public func jsonData() -> Data {
        (try? RemoteJSON.encoder().encode(self)) ?? Data()
    }
}

/// Telefon → Mac (WebSocket).
public enum ClientMessage: Equatable, Sendable {
    case auth(token: String)
    case sendText(sessionId: String, text: String)
    case interrupt(sessionId: String)
}

extension ClientMessage: Decodable {
    private enum Keys: String, CodingKey { case type, token, sessionId, text }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "auth":
            self = .auth(token: try container.decode(String.self, forKey: .token))
        case "send.text":
            self = .sendText(sessionId: try container.decode(String.self, forKey: .sessionId),
                             text: try container.decode(String.self, forKey: .text))
        case "interrupt":
            self = .interrupt(sessionId: try container.decode(String.self, forKey: .sessionId))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "unknown type \(other)")
        }
    }
}

public enum RemoteJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum RemoteSnapshot {
    /// Telefondaki liste: bekleyenler üstte (spec §5), aynı sınıfta store sırası.
    public static func sessions(_ sessions: [AgentStore.Session], canSend: (String) -> Bool) -> [RemoteSession] {
        let mapped = sessions.map { session in
            RemoteSession(id: session.id, title: session.title, status: status(session.state), detail: detail(session.state),
                          summary: session.workSummary, todos: session.todos.map(todo),
                          finishedUnseen: session.unseenFinish && session.state != .exited,
                          canSend: session.state != .exited && canSend(session.id))
        }
        return mapped.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    static func rank(_ session: RemoteSession) -> Int {
        switch session.status {
        case .permission: 0
        case .question: 1
        case .working: 2
        case .idle: session.finishedUnseen ? 3 : 4
        case .starting: 5
        case .exited: 6
        }
    }

    static func status(_ state: AgentState) -> RemoteSession.Status {
        switch state {
        case .starting: .starting
        case .idle: .idle
        case .working: .working
        case .waiting(.permission): .permission
        case .waiting(.question): .question
        case .exited: .exited
        }
    }

    static func detail(_ state: AgentState) -> String? {
        switch state {
        case .working(let tool): tool
        case .waiting(.permission(let text)), .waiting(.question(let text)): text.isEmpty ? nil : text
        default: nil
        }
    }

    static func todo(_ item: TodoItem) -> RemoteTodo {
        let status: RemoteTodo.Status = switch item.status {
        case .pending: .pending
        case .inProgress: .inProgress
        case .done: .done
        }
        return RemoteTodo(title: item.title, status: status)
    }
}
```

- [ ] **Step 4: GREEN gör**

Run: `swift test --filter RemoteProtocolTests`
Expected: 6 test PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentOfficeCore/RemoteProtocol.swift Tests/AgentOfficeCoreTests/RemoteProtocolTests.swift
git commit -m "Remote access: protocol types and the session snapshot the phone sees"
```

---

### Task 2: Eşleştirme kodu ve cihaz token'ları

**Files:**
- Create: `Sources/AgentOfficeCore/RemoteAuth.swift`
- Test: `Tests/AgentOfficeCoreTests/RemoteAuthTests.swift`

**Interfaces:**
- Consumes: `RemoteJSON` (Task 1).
- Produces:
  - `public struct PairedDevice: Codable, Equatable, Identifiable, Sendable { id: String; name: String; tokenHash: String; pairedAt: Date; lastSeen: Date? }`
  - `public final class RemoteAuth: @unchecked Sendable`
    - `init(fileURL: URL, now: @escaping @Sendable () -> Date = { Date() })`
    - `static let codeLifetime: TimeInterval = 120`, `static let maxAttempts = 5`
    - `var devices: [PairedDevice]`, `var currentCode: String?`
    - `@discardableResult func newPairingCode() -> String`
    - `func pair(code: String, deviceName: String) -> String?` (token)
    - `func device(forToken token: String) -> PairedDevice?` (lastSeen'i günceller)
    - `func revoke(_ id: String)`
    - `var onChange: (@Sendable () -> Void)?`

- [ ] **Step 1: Başarısız testleri yaz**

```swift
import Foundation
import Testing
@testable import AgentOfficeCore

final class TestClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}

@Suite struct RemoteAuthTests {
    func makeAuth(_ clock: TestClock = TestClock()) -> (RemoteAuth, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("remote-\(UUID().uuidString)/devices.json")
        return (RemoteAuth(fileURL: url, now: { clock.date }), url)
    }

    @Test func correctCodePairsOnce() throws {
        let (auth, _) = makeAuth()
        let code = auth.newPairingCode()
        #expect(code.count == 6 && code.allSatisfy(\.isNumber))
        let token = try #require(auth.pair(code: code, deviceName: "iPhone"))
        #expect(auth.device(forToken: token)?.name == "iPhone")
        #expect(auth.pair(code: code, deviceName: "Other") == nil)
        #expect(auth.currentCode == nil)
    }

    @Test func fiveWrongAttemptsBurnTheCode() {
        let (auth, _) = makeAuth()
        let code = auth.newPairingCode()
        let wrong = code == "000000" ? "111111" : "000000"
        for _ in 0..<RemoteAuth.maxAttempts { #expect(auth.pair(code: wrong, deviceName: "x") == nil) }
        #expect(auth.pair(code: code, deviceName: "x") == nil)
    }

    @Test func codeExpiresAfterTwoMinutes() {
        let clock = TestClock()
        let (auth, _) = makeAuth(clock)
        let code = auth.newPairingCode()
        clock.date += RemoteAuth.codeLifetime + 1
        #expect(auth.currentCode == nil)
        #expect(auth.pair(code: code, deviceName: "x") == nil)
    }

    @Test func revokedTokenStopsWorking() throws {
        let (auth, _) = makeAuth()
        let token = try #require(auth.pair(code: auth.newPairingCode(), deviceName: "iPhone"))
        let device = try #require(auth.device(forToken: token))
        auth.revoke(device.id)
        #expect(auth.device(forToken: token) == nil)
        #expect(auth.devices.isEmpty)
    }

    @Test func onlyTheHashIsStoredAndItSurvivesRestart() throws {
        let (auth, url) = makeAuth()
        let token = try #require(auth.pair(code: auth.newPairingCode(), deviceName: "iPhone"))
        let file = try String(contentsOf: url, encoding: .utf8)
        #expect(!file.contains(token))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        let reloaded = RemoteAuth(fileURL: url)
        #expect(reloaded.device(forToken: token)?.name == "iPhone")
    }

    @Test func blankDeviceNameFallsBack() throws {
        let (auth, _) = makeAuth()
        let token = try #require(auth.pair(code: auth.newPairingCode(), deviceName: "   "))
        #expect(auth.device(forToken: token)?.name == "Phone")
    }
}
```

- [ ] **Step 2: RED gör**

Run: `swift test --filter RemoteAuthTests`
Expected: derleme hatası (`RemoteAuth` yok).

- [ ] **Step 3: Uygula**

```swift
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
```

- [ ] **Step 4: GREEN gör**

Run: `swift test --filter RemoteAuthTests`
Expected: 6 test PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentOfficeCore/RemoteAuth.swift Tests/AgentOfficeCoreTests/RemoteAuthTests.swift
git commit -m "Remote access: one-time pairing codes and hashed device tokens"
```

---

### Task 3: Dinlenecek arayüzün seçimi

**Files:**
- Create: `Sources/AgentOfficeCore/RemoteInterfaces.swift`
- Test: `Tests/AgentOfficeCoreTests/RemoteInterfacesTests.swift`

**Interfaces:**
- Produces:
  - `public enum RemoteMode: String, CaseIterable, Sendable { case tailscale, localNetwork }`
  - `public struct NetInterface: Equatable, Sendable { name: String; address: String }` (public init)
  - `public enum RemoteInterfaces { static func current() -> [NetInterface]; static func isTailscale(_:) -> Bool; static func isPrivateLAN(_:) -> Bool; static func bindAddress(mode: RemoteMode, interfaces: [NetInterface]) -> NetInterface? }`

- [ ] **Step 1: Başarısız testleri yaz**

```swift
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
```

- [ ] **Step 2: RED gör**

Run: `swift test --filter RemoteInterfacesTests`
Expected: derleme hatası.

- [ ] **Step 3: Uygula**

```swift
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
```

- [ ] **Step 4: GREEN gör**

Run: `swift test --filter RemoteInterfacesTests`
Expected: 5 test PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentOfficeCore/RemoteInterfaces.swift Tests/AgentOfficeCoreTests/RemoteInterfacesTests.swift
git commit -m "Remote access: pick the Tailscale or local network address to listen on"
```

---

### Task 4: Transkriptten sohbet mesajları

**Files:**
- Create: `Sources/AgentOfficeCore/TranscriptReader.swift`
- Test: `Tests/AgentOfficeCoreTests/TranscriptReaderTests.swift`

**Interfaces:**
- Consumes: `RemoteMessage`, `TranscriptPage` (Task 1); `JSONValue`, `ClaudeNormalizer.summary(of:)` (mevcut, internal).
- Produces:
  - `public enum TranscriptReader`
    - `static func messages(fromLines lines: [Substring]) -> [RemoteMessage]`
    - `static func read(url: URL, from offset: UInt64, maxBytes: Int = 16 << 20) -> TranscriptPage?`
    - `static func tail(url: URL, maxMessages: Int = 200, tailBytes: UInt64 = 2 << 20) -> TranscriptPage?`

Kurallar (bu oturumun gerçek JSONL'inden çıkarıldı): her satır bir kayıt. Yalnızca `type` `user` ve `assistant` kayıtları; `isSidechain == true` ve `isMeta == true` atlanır. Kullanıcı: `message.content` metinse ve `<` ile başlamıyorsa (komut, sistem etiketleri) kullanıcı mesajı; dizi ise `text` blokları aynı kuralla, `tool_result` atlanır. Asistan: `text` blokları asistan mesajı, `tool_use` blokları `"<Tool> <özet>"` tool satırı, `thinking` atlanır. Mesaj kimliği `"<uuid>:<blok sırası>"`, zaman `timestamp`.

- [ ] **Step 1: Başarısız testleri yaz**

```swift
import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct TranscriptReaderTests {
    static let user = #"{"type":"user","uuid":"u1","timestamp":"2026-10-15T10:00:00Z","isSidechain":false,"message":{"role":"user","content":"Testleri çalıştır"}}"#
    static let thinking = #"{"type":"assistant","uuid":"a0","isSidechain":false,"message":{"content":[{"type":"thinking","thinking":"..."}]}}"#
    static let tool = #"{"type":"assistant","uuid":"a1","isSidechain":false,"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"swift test"}}]}}"#
    static let result = #"{"type":"user","uuid":"u2","isSidechain":false,"message":{"content":[{"type":"tool_result","content":"ok"}]}}"#
    static let answer = #"{"type":"assistant","uuid":"a2","isSidechain":false,"message":{"content":[{"type":"text","text":"Hepsi geçti."}]}}"#
    static let side = #"{"type":"assistant","uuid":"s1","isSidechain":true,"message":{"content":[{"type":"text","text":"alt ajan"}]}}"#
    static let meta = #"{"type":"user","uuid":"m1","isMeta":true,"isSidechain":false,"message":{"content":"meta"}}"#
    static let command = #"{"type":"user","uuid":"c1","isSidechain":false,"message":{"content":"<command-name>/clear</command-name>"}}"#
    static let title = #"{"type":"ai-title","aiTitle":"Testler"}"#

    func file(_ lines: [String], trailingNewline: Bool = true) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID().uuidString).jsonl")
        try Data((lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")).utf8).write(to: url)
        return url
    }

    @Test func keepsTheConversationOnly() {
        let lines = [Self.user, Self.thinking, Self.tool, Self.result, Self.answer, Self.side, Self.meta, Self.command, Self.title]
        let messages = TranscriptReader.messages(fromLines: lines.map { Substring($0) })
        #expect(messages.map(\.role) == [.user, .tool, .assistant])
        #expect(messages.map(\.text) == ["Testleri çalıştır", "Bash swift test", "Hepsi geçti."])
        #expect(messages[0].id == "u1:0" && messages[0].time == "2026-10-15T10:00:00Z")
    }

    @Test func readsFromTheCursor() throws {
        let url = try file([Self.user, Self.answer])
        let first = try #require(TranscriptReader.read(url: url, from: 0))
        #expect(first.messages.count == 2)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((Self.tool + "\n").utf8))
        try handle.close()
        let next = try #require(TranscriptReader.read(url: url, from: first.cursor))
        #expect(next.messages.map(\.text) == ["Bash swift test"])
    }

    @Test func partialLineIsNotConsumed() throws {
        let url = try file([Self.user, String(Self.answer.prefix(30))], trailingNewline: false)
        let page = try #require(TranscriptReader.read(url: url, from: 0))
        #expect(page.messages.map(\.text) == ["Testleri çalıştır"])
        #expect(page.cursor == UInt64(Self.user.utf8.count + 1))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((String(Self.answer.dropFirst(30)) + "\n").utf8))
        try handle.close()
        let next = try #require(TranscriptReader.read(url: url, from: page.cursor))
        #expect(next.messages.map(\.text) == ["Hepsi geçti."])
    }

    @Test func tailKeepsTheLastMessages() throws {
        let url = try file(Array(repeating: Self.answer, count: 10))
        let page = try #require(TranscriptReader.tail(url: url, maxMessages: 3))
        #expect(page.messages.count == 3)
        #expect(page.cursor == UInt64((Self.answer.utf8.count + 1) * 10))
    }

    @Test func missingFileIsNil() {
        #expect(TranscriptReader.read(url: URL(fileURLWithPath: "/nonexistent/x.jsonl"), from: 0) == nil)
    }

    @Test func cursorPastTheEndStaysAtTheEnd() throws {
        let url = try file([Self.user])
        let page = try #require(TranscriptReader.read(url: url, from: 10_000))
        #expect(page.messages.isEmpty)
        #expect(page.cursor == UInt64(Self.user.utf8.count + 1))
    }
}
```

- [ ] **Step 2: RED gör**

Run: `swift test --filter TranscriptReaderTests`
Expected: derleme hatası.

- [ ] **Step 3: Uygula**

```swift
import Foundation

/// Claude Code'un JSONL kaydından telefonda gösterilecek sohbet (spec §5): ana konuşma, tool çağrıları tek satır.
/// Dosya okuyan fonksiyonlar ana thread'de çağrılmamalı.
public enum TranscriptReader {
    public static func messages(fromLines lines: [Substring]) -> [RemoteMessage] {
        lines.flatMap(messages(fromLine:))
    }

    static func messages(fromLine line: Substring) -> [RemoteMessage] {
        guard line.contains("\"type\":\"user\"") || line.contains("\"type\":\"assistant\""),
              let record = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)),
              let type = record["type"]?.string, type == "user" || type == "assistant",
              record["isSidechain"] != .bool(true), record["isMeta"] != .bool(true),
              let uuid = record["uuid"]?.string else { return [] }
        let time = record["timestamp"]?.string
        let content = record["message"]?["content"]
        if let text = content?.string {
            guard type == "user", let text = userText(text) else { return [] }
            return [RemoteMessage(id: "\(uuid):0", role: .user, text: text, time: time)]
        }
        return (content?.array ?? []).enumerated().compactMap { (index, block) -> RemoteMessage? in
            let id = "\(uuid):\(index)"
            switch (type, block["type"]?.string) {
            case ("user", "text"):
                return block["text"]?.string.flatMap(userText).map { RemoteMessage(id: id, role: .user, text: $0, time: time) }
            case ("assistant", "text"):
                guard let text = block["text"]?.string, !text.isEmpty else { return nil }
                return RemoteMessage(id: id, role: .assistant, text: text, time: time)
            case ("assistant", "tool_use"):
                let name = block["name"]?.string ?? "?"
                let summary = ClaudeNormalizer.summary(of: block["input"])
                return RemoteMessage(id: id, role: .tool, text: summary.map { "\(name) \($0)" } ?? name, time: time)
            default:
                return nil
            }
        }
    }

    /// Komut ve sistem etiketleri (`<command-name>…`, `<local-command-stdout>…`) sohbet değil.
    static func userText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasPrefix("<") ? nil : trimmed
    }

    /// `offset`'ten itibaren tamamlanmış satırları okur; yarım kalan son satır bir sonraki okumaya kalır.
    /// `maxBytes` içinde hiç satır sonu yoksa (dev bir satır) o kısım atlanır, okuma takılı kalmaz.
    public static func read(url: URL, from offset: UInt64, maxBytes: Int = 16 << 20) -> TranscriptPage? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        guard offset < size else { return TranscriptPage(messages: [], cursor: size) }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.read(upToCount: maxBytes), !data.isEmpty else { return nil }
        guard let newline = data.lastIndex(of: 0x0A) else {
            let skipped = data.count >= maxBytes ? UInt64(data.count) : 0
            return TranscriptPage(messages: [], cursor: offset + skipped)
        }
        let complete = data[data.startIndex...newline]
        let lines = String(decoding: complete, as: UTF8.self).split(separator: "\n")
        return TranscriptPage(messages: messages(fromLines: lines), cursor: offset + UInt64(complete.count))
    }

    /// İlk açılış: dosyanın sonundan en çok `maxMessages` mesaj. Ortadan başlanırsa ilk satır yarımdır ve
    /// JSON olarak çözülemediği için kendiliğinden atlanır.
    public static func tail(url: URL, maxMessages: Int = 200, tailBytes: UInt64 = 2 << 20) -> TranscriptPage? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else { return nil }
        let start = size > tailBytes ? size - tailBytes : 0
        guard size > 0 else { return TranscriptPage(messages: [], cursor: 0) }
        guard var page = read(url: url, from: start, maxBytes: Int(size - start)) else { return nil }
        page.messages = Array(page.messages.suffix(maxMessages))
        return page
    }
}
```

- [ ] **Step 4: GREEN gör**

Run: `swift test --filter TranscriptReaderTests`
Expected: 6 test PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentOfficeCore/TranscriptReader.swift Tests/AgentOfficeCoreTests/TranscriptReaderTests.swift
git commit -m "Remote access: read the conversation from the Claude transcript, resuming at a byte cursor"
```

---

### Task 5: HTTP ve WebSocket çerçeveleme

**Files:**
- Create: `Sources/AgentOfficeCore/HTTPMessage.swift`, `Sources/AgentOfficeCore/WebSocketFrame.swift`
- Test: `Tests/AgentOfficeCoreTests/HTTPMessageTests.swift`, `Tests/AgentOfficeCoreTests/WebSocketFrameTests.swift`

**Interfaces:**
- Produces:
  - `public struct HTTPRequest: Equatable, Sendable { method, path: String; query: [String: String]; headers: [String: String] (küçük harf anahtar); body: Data; func header(_:) -> String?; var bearerToken: String?; var isWebSocketUpgrade: Bool }`
  - `public enum HTTPParseResult: Equatable, Sendable { case incomplete, invalid(status: Int), request(HTTPRequest, consumed: Int) }`
  - `public enum HTTPParser { static let maxHeaderBytes = 16 * 1024; static let maxBodyBytes = 64 * 1024; static func parse(_ input: Data) -> HTTPParseResult }`
  - `public struct HTTPResponse: Equatable, Sendable { status: Int; contentType: String; body: Data; static func json<T: Encodable>(_:status:) -> HTTPResponse; static func error(_ status: Int, _ code: String) -> HTTPResponse; func serialized() -> Data }`
  - `public enum WebSocket { static func acceptKey(for:) -> String; static func handshake(key:) -> Data; enum Opcode: UInt8; struct Frame: Equatable, Sendable { opcode: Opcode; payload: Data }; enum DecodeResult: Equatable, Sendable { incomplete, invalid, frame(Frame, consumed: Int) }; static let maxPayload = 1 << 20; static func encode(_ opcode: Opcode, _ payload: Data) -> Data; static func decode(_ input: Data) -> DecodeResult; static func closePayload(code: UInt16) -> Data }`

- [ ] **Step 1: Başarısız testleri yaz**

`HTTPMessageTests.swift`:

```swift
import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct HTTPMessageTests {
    func parse(_ text: String) -> HTTPParseResult { HTTPParser.parse(Data(text.utf8)) }

    @Test func parsesGetWithQueryAndBearer() throws {
        let raw = "GET /api/sessions/s1/transcript?after=120 HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer abc\r\n\r\n"
        guard case .request(let request, let consumed) = parse(raw) else { Issue.record("not parsed"); return }
        #expect(request.method == "GET")
        #expect(request.path == "/api/sessions/s1/transcript")
        #expect(request.query["after"] == "120")
        #expect(request.bearerToken == "abc")
        #expect(consumed == raw.utf8.count)
    }

    @Test func waitsForTheWholeBody() {
        #expect(parse("POST /api/pair HTTP/1.1\r\nContent-Length: 10\r\n\r\n{\"a\"") == .incomplete)
        #expect(parse("GET / HTTP/1.1\r\nHost: x\r\n") == .incomplete)
    }

    @Test func readsTheBody() {
        guard case .request(let request, _) = parse("POST /api/pair HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}") else {
            Issue.record("not parsed"); return
        }
        #expect(request.body == Data("{}".utf8))
    }

    @Test func rejectsOversizedAndBrokenRequests() {
        let huge = "GET / HTTP/1.1\r\nX: " + String(repeating: "a", count: HTTPParser.maxHeaderBytes) + "\r\n\r\n"
        #expect(parse(huge) == .invalid(status: 431))
        #expect(parse("POST / HTTP/1.1\r\nContent-Length: 999999\r\n\r\n") == .invalid(status: 413))
        #expect(parse("NONSENSE\r\n\r\n") == .invalid(status: 400))
    }

    @Test func detectsWebSocketUpgrade() {
        let raw = "GET /api/stream HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
        guard case .request(let request, _) = parse(raw) else { Issue.record("not parsed"); return }
        #expect(request.isWebSocketUpgrade)
    }

    @Test func responseSerializes() {
        let text = String(decoding: HTTPResponse.error(401, "unauthorized").serialized(), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
        #expect(text.contains("Content-Type: application/json; charset=utf-8\r\n"))
        #expect(text.contains("Cache-Control: no-store\r\n"))
        #expect(text.hasSuffix("\r\n\r\n{\"error\":\"unauthorized\"}"))
    }
}
```

`WebSocketFrameTests.swift`:

```swift
import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct WebSocketFrameTests {
    @Test func acceptKeyMatchesRFC6455() {
        #expect(WebSocket.acceptKey(for: "dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    @Test func decodesTheMaskedHelloFromTheRFC() {
        let bytes: [UInt8] = [0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58]
        #expect(WebSocket.decode(Data(bytes)) == .frame(WebSocket.Frame(opcode: .text, payload: Data("Hello".utf8)), consumed: 11))
    }

    @Test func incompleteAndInvalidFrames() {
        #expect(WebSocket.decode(Data([0x81])) == .incomplete)
        #expect(WebSocket.decode(Data([0x81, 0x85, 0x37, 0xfa])) == .incomplete)
        // Maskesiz istemci çerçevesi
        #expect(WebSocket.decode(Data([0x81, 0x05]) + Data("Hello".utf8)) == .invalid)
        // Parçalı mesaj (FIN yok)
        #expect(WebSocket.decode(Data([0x01, 0x80, 0, 0, 0, 0])) == .invalid)
        // Sınırı aşan uzunluk
        #expect(WebSocket.decode(Data([0x81, 0xFF, 0, 0, 0, 0, 0x10, 0, 0, 0])) == .invalid)
    }

    @Test func encodesLengthsUnmasked() {
        #expect(Array(WebSocket.encode(.text, Data("hi".utf8))) == [0x81, 0x02, 0x68, 0x69])
        let medium = WebSocket.encode(.text, Data(count: 300))
        #expect(Array(medium.prefix(4)) == [0x81, 126, 0x01, 0x2C])
        let large = WebSocket.encode(.binary, Data(count: 70_000))
        #expect(Array(large.prefix(10)) == [0x82, 127, 0, 0, 0, 0, 0, 0x01, 0x11, 0x70])
    }

    @Test func closePayloadCarriesTheCode() {
        #expect(Array(WebSocket.closePayload(code: 4401)) == [0x11, 0x31])
    }
}
```

- [ ] **Step 2: RED gör**

Run: `swift test --filter "HTTPMessageTests|WebSocketFrameTests"`
Expected: derleme hatası.

- [ ] **Step 3: Uygula** — `HTTPMessage.swift`:

```swift
import Foundation

public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    /// Anahtarlar küçük harf.
    public var headers: [String: String]
    public var body: Data

    public func header(_ name: String) -> String? { headers[name.lowercased()] }

    public var bearerToken: String? {
        guard let value = header("authorization"), value.hasPrefix("Bearer ") else { return nil }
        return String(value.dropFirst("Bearer ".count))
    }

    public var isWebSocketUpgrade: Bool {
        header("upgrade")?.lowercased() == "websocket" && header("sec-websocket-key") != nil
    }
}

public enum HTTPParseResult: Equatable, Sendable {
    case incomplete
    case invalid(status: Int)
    case request(HTTPRequest, consumed: Int)
}

/// Uzaktan erişim sunucusunun tek ihtiyacı kadar HTTP/1.1: tek istek, `Content-Length` gövde, chunked yok.
public enum HTTPParser {
    public static let maxHeaderBytes = 16 * 1024
    public static let maxBodyBytes = 64 * 1024

    public static func parse(_ input: Data) -> HTTPParseResult {
        let buffer = Data(input)  // indeksler 0'dan başlasın
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > maxHeaderBytes ? .invalid(status: 431) : .incomplete
        }
        guard end.lowerBound <= maxHeaderBytes else { return .invalid(status: 431) }
        var lines = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return .invalid(status: 400) }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid(status: 400) }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let length = Int(headers["content-length"] ?? "0"), length >= 0 else { return .invalid(status: 400) }
        guard length <= maxBodyBytes else { return .invalid(status: 413) }
        let bodyStart = end.upperBound
        guard buffer.count - bodyStart >= length else { return .incomplete }
        let components = URLComponents(string: String(parts[1]))
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let request = HTTPRequest(method: String(parts[0]), path: components?.path ?? String(parts[1]), query: query,
                                  headers: headers, body: Data(buffer[bodyStart..<(bodyStart + length)]))
        return .request(request, consumed: bodyStart + length)
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public var status: Int
    public var contentType: String
    public var body: Data

    public init(status: Int, contentType: String, body: Data) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }

    public static func json<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        guard let body = try? RemoteJSON.encoder().encode(value) else { return error(500, "encoding") }
        return HTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: body)
    }

    public static func error(_ status: Int, _ code: String) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: Data(#"{"error":"\#(code)"}"#.utf8))
    }

    /// Her cevaptan sonra bağlantı kapanır (`Connection: close`).
    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "X-Content-Type-Options: nosniff\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 413: "Payload Too Large"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        default: "Status"
        }
    }
}
```

`WebSocketFrame.swift`:

```swift
import CryptoKit
import Foundation

/// RFC 6455'in sunucu tarafı: el sıkışma ve çerçeveler. Parçalı mesaj desteklenmez (tarayıcılar küçük metinleri
/// tek çerçevede yollar); istemci çerçevesi maskeli olmalı.
public enum WebSocket {
    static let guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    public static let maxPayload = 1 << 20

    public enum Opcode: UInt8, Sendable {
        case continuation = 0, text = 1, binary = 2, close = 8, ping = 9, pong = 10
    }

    public struct Frame: Equatable, Sendable {
        public var opcode: Opcode
        public var payload: Data

        public init(opcode: Opcode, payload: Data) {
            self.opcode = opcode
            self.payload = payload
        }
    }

    public enum DecodeResult: Equatable, Sendable {
        case incomplete
        case invalid
        case frame(Frame, consumed: Int)
    }

    public static func acceptKey(for key: String) -> String {
        Data(Insecure.SHA1.hash(data: Data((key + guid).utf8))).base64EncodedString()
    }

    public static func handshake(key: String) -> Data {
        Data(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
              + "Sec-WebSocket-Accept: \(acceptKey(for: key))\r\n\r\n").utf8)
    }

    /// Sunucu çerçevesi: maskesiz, tek parça.
    public static func encode(_ opcode: Opcode, _ payload: Data) -> Data {
        var out = Data([0x80 | opcode.rawValue])
        switch payload.count {
        case ..<126:
            out.append(UInt8(payload.count))
        case ..<65_536:
            out.append(126)
            out.append(UInt8(payload.count >> 8))
            out.append(UInt8(payload.count & 0xFF))
        default:
            out.append(127)
            for shift in stride(from: 56, through: 0, by: -8) { out.append(UInt8((UInt64(payload.count) >> UInt64(shift)) & 0xFF)) }
        }
        return out + payload
    }

    public static func decode(_ input: Data) -> DecodeResult {
        let buffer = Data(input)
        let header = [UInt8](buffer.prefix(14))
        guard header.count >= 2 else { return .incomplete }
        guard header[0] & 0x80 != 0, header[0] & 0x70 == 0,
              let opcode = Opcode(rawValue: header[0] & 0x0F), opcode != .continuation,
              header[1] & 0x80 != 0 else { return .invalid }
        var length = Int(header[1] & 0x7F)
        var index = 2
        if length == 126 {
            guard header.count >= 4 else { return .incomplete }
            length = Int(header[2]) << 8 | Int(header[3])
            index = 4
        } else if length == 127 {
            guard header.count >= 10 else { return .incomplete }
            var value: UInt64 = 0
            for byte in header[2..<10] { value = value << 8 | UInt64(byte) }
            guard value <= UInt64(maxPayload) else { return .invalid }
            length = Int(value)
            index = 10
        }
        guard length <= maxPayload, opcode.rawValue < 8 || length <= 125 else { return .invalid }
        guard header.count >= index + 4 else { return .incomplete }
        let mask = Array(header[index..<(index + 4)])
        index += 4
        guard buffer.count >= index + length else { return .incomplete }
        var payload = [UInt8](buffer[index..<(index + length)])
        for i in payload.indices { payload[i] ^= mask[i % 4] }
        return .frame(Frame(opcode: opcode, payload: Data(payload)), consumed: index + length)
    }

    public static func closePayload(code: UInt16) -> Data {
        Data([UInt8(code >> 8), UInt8(code & 0xFF)])
    }
}
```

- [ ] **Step 4: GREEN gör**

Run: `swift test --filter "HTTPMessageTests|WebSocketFrameTests"`
Expected: 11 test PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentOfficeCore/HTTPMessage.swift Sources/AgentOfficeCore/WebSocketFrame.swift \
        Tests/AgentOfficeCoreTests/HTTPMessageTests.swift Tests/AgentOfficeCoreTests/WebSocketFrameTests.swift
git commit -m "Remote access: minimal HTTP/1.1 parsing and RFC 6455 WebSocket frames"
```

---

### Task 6: HTTP uçları ve PWA dosyaları

**Files:**
- Create: `Sources/AgentOfficeCore/RemoteRoutes.swift`
- Test: `Tests/AgentOfficeCoreTests/RemoteRoutesTests.swift`

**Interfaces:**
- Consumes: `HTTPRequest`, `HTTPResponse` (Task 5), `RemoteAuth` (Task 2), `RemoteSession`, `TranscriptPage` (Task 1).
- Produces:
  - `public struct RemoteRoutes: Sendable { auth: RemoteAuth; staticRoot: URL?; sessions: @Sendable () async -> [RemoteSession]; transcript: @Sendable (_ sessionId: String, _ after: UInt64?) async -> TranscriptPage?; init(...); func respond(to: HTTPRequest) async -> HTTPResponse }`
  - `public enum RemoteStatic { static let files: [String: String]; static let folder = "Remote"; static func find(bundleResources: URL?, repoRoot: URL, fileExists: (String) -> Bool = ...) -> URL? }`

Uçlar: `GET /` → `index.html`; `GET /<ad>` yalnızca `RemoteStatic.files` listesindekiler; `POST /api/pair` (gövde `{"code","deviceName"}` → `{"token"}`); `GET /api/sessions`; `GET /api/sessions/{id}/transcript[?after=N]` (`after` yoksa son mesajlar). `/api/` altındaki her şey (pair hariç) Bearer token ister.

- [ ] **Step 1: Başarısız testleri yaz**

```swift
import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct RemoteRoutesTests {
    func makeRoutes(transcript: TranscriptPage? = nil) throws -> (RemoteRoutes, RemoteAuth) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("remote-static-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("<h1>Slash</h1>".utf8).write(to: dir.appendingPathComponent("index.html"))
        try Data("console.log(1)".utf8).write(to: dir.appendingPathComponent("app.js"))
        try Data("secret".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        let auth = RemoteAuth(fileURL: dir.appendingPathComponent("devices.json"))
        let session = RemoteSession(id: "s1", title: "proj", status: .idle, detail: nil, summary: nil, todos: [],
                                    finishedUnseen: false, canSend: true)
        let routes = RemoteRoutes(auth: auth, staticRoot: dir, sessions: { [session] in [session] }, transcript: { id, _ in id == "s1" ? transcript : nil })
        return (routes, auth)
    }

    func request(_ method: String, _ path: String, token: String? = nil, body: String = "", query: [String: String] = [:]) -> HTTPRequest {
        var headers: [String: String] = [:]
        if let token { headers["authorization"] = "Bearer \(token)" }
        return HTTPRequest(method: method, path: path, query: query, headers: headers, body: Data(body.utf8))
    }

    @Test func servesOnlyListedStaticFiles() async throws {
        let (routes, _) = try makeRoutes()
        let index = await routes.respond(to: request("GET", "/"))
        #expect(index.status == 200 && index.contentType.hasPrefix("text/html") && index.body == Data("<h1>Slash</h1>".utf8))
        #expect(await routes.respond(to: request("GET", "/app.js")).contentType.hasPrefix("text/javascript"))
        #expect(await routes.respond(to: request("GET", "/notes.txt")).status == 404)
        #expect(await routes.respond(to: request("GET", "/../devices.json")).status == 404)
    }

    @Test func apiNeedsAToken() async throws {
        let (routes, _) = try makeRoutes()
        #expect(await routes.respond(to: request("GET", "/api/sessions")).status == 401)
        #expect(await routes.respond(to: request("GET", "/api/sessions", token: "wrong")).status == 401)
    }

    @Test func pairingThenSessions() async throws {
        let (routes, auth) = try makeRoutes()
        let code = auth.newPairingCode()
        let paired = await routes.respond(to: request("POST", "/api/pair", body: #"{"code":"\#(code)","deviceName":"iPhone"}"#))
        #expect(paired.status == 200)
        let token = try #require((try JSONSerialization.jsonObject(with: paired.body) as? [String: String])?["token"])
        let list = await routes.respond(to: request("GET", "/api/sessions", token: token))
        #expect(list.status == 200)
        #expect(try RemoteJSON.decoder().decode([RemoteSession].self, from: list.body).map(\.id) == ["s1"])
    }

    @Test func wrongCodeIsRefused() async throws {
        let (routes, auth) = try makeRoutes()
        auth.newPairingCode()
        #expect(await routes.respond(to: request("POST", "/api/pair", body: #"{"code":"x","deviceName":"a"}"#)).status == 401)
        #expect(await routes.respond(to: request("POST", "/api/pair", body: "nope")).status == 400)
    }

    @Test func transcriptRoute() async throws {
        let page = TranscriptPage(messages: [RemoteMessage(id: "u:0", role: .user, text: "hi", time: nil)], cursor: 42)
        let (routes, auth) = try makeRoutes(transcript: page)
        let token = try #require(auth.pair(code: auth.newPairingCode(), deviceName: "p"))
        let found = await routes.respond(to: request("GET", "/api/sessions/s1/transcript", token: token, query: ["after": "10"]))
        #expect(try RemoteJSON.decoder().decode(TranscriptPage.self, from: found.body) == page)
        #expect(await routes.respond(to: request("GET", "/api/sessions/zz/transcript", token: token)).status == 404)
        #expect(await routes.respond(to: request("DELETE", "/api/sessions", token: token)).status == 405)
    }

    @Test func findsTheStaticFolder() {
        let repo = URL(fileURLWithPath: "/repo")
        let found = RemoteStatic.find(bundleResources: nil, repoRoot: repo, fileExists: { $0 == "/repo/Resources/Remote/index.html" })
        #expect(found?.path == "/repo/Resources/Remote")
        #expect(RemoteStatic.find(bundleResources: nil, repoRoot: repo, fileExists: { _ in false }) == nil)
    }
}
```

- [ ] **Step 2: RED gör**

Run: `swift test --filter RemoteRoutesTests`
Expected: derleme hatası.

- [ ] **Step 3: Uygula**

```swift
import Foundation

/// Telefona sunulan web uygulamasının dosyaları: yalnızca bu adlar sunulur (yol gezintisi yok).
public enum RemoteStatic {
    public static let folder = "Remote"
    public static let files: [String: String] = [
        "index.html": "text/html; charset=utf-8",
        "app.js": "text/javascript; charset=utf-8",
        "app.css": "text/css; charset=utf-8",
        "manifest.json": "application/manifest+json",
    ]

    /// Önce uygulama paketi, sonra depo (paketsiz çalışma).
    public static func find(bundleResources: URL?, repoRoot: URL,
                            fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL? {
        let candidates = [bundleResources?.appendingPathComponent(folder),
                          repoRoot.appendingPathComponent("Resources/\(folder)")].compactMap { $0 }
        return candidates.first { fileExists($0.appendingPathComponent("index.html").path) }
    }
}

/// HTTP uçları (spec §7). Ağdan bağımsız: istek alır, cevap döner.
public struct RemoteRoutes: Sendable {
    public var auth: RemoteAuth
    public var staticRoot: URL?
    public var sessions: @Sendable () async -> [RemoteSession]
    /// `after` nil ise son mesajlar (ilk açılış).
    public var transcript: @Sendable (_ sessionId: String, _ after: UInt64?) async -> TranscriptPage?

    public init(auth: RemoteAuth, staticRoot: URL?, sessions: @escaping @Sendable () async -> [RemoteSession],
                transcript: @escaping @Sendable (_ sessionId: String, _ after: UInt64?) async -> TranscriptPage?) {
        self.auth = auth
        self.staticRoot = staticRoot
        self.sessions = sessions
        self.transcript = transcript
    }

    public func respond(to request: HTTPRequest) async -> HTTPResponse {
        if request.method == "GET", request.path == "/" { return staticFile("index.html") }
        if request.method == "POST", request.path == "/api/pair" { return pair(request) }
        if request.path.hasPrefix("/api/") {
            guard let token = request.bearerToken, auth.device(forToken: token) != nil else { return .error(401, "unauthorized") }
            return await api(request)
        }
        let name = String(request.path.dropFirst())
        if request.method == "GET", RemoteStatic.files[name] != nil { return staticFile(name) }
        return .error(404, "not_found")
    }

    func api(_ request: HTTPRequest) async -> HTTPResponse {
        guard request.method == "GET" else { return .error(405, "method_not_allowed") }
        let parts = request.path.split(separator: "/").map(String.init)
        if parts == ["api", "sessions"] { return .json(await sessions()) }
        if parts.count == 4, parts[1] == "sessions", parts[3] == "transcript" {
            let after = request.query["after"].flatMap { UInt64($0) }
            guard let page = await transcript(parts[2], after) else { return .error(404, "no_transcript") }
            return .json(page)
        }
        return .error(404, "not_found")
    }

    func pair(_ request: HTTPRequest) -> HTTPResponse {
        struct Body: Decodable {
            let code: String
            let deviceName: String
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: request.body) else { return .error(400, "bad_request") }
        guard let token = auth.pair(code: body.code, deviceName: body.deviceName) else { return .error(401, "wrong_code") }
        return .json(["token": token])
    }

    func staticFile(_ name: String) -> HTTPResponse {
        guard let type = RemoteStatic.files[name], let root = staticRoot,
              let data = try? Data(contentsOf: root.appendingPathComponent(name)) else { return .error(404, "not_found") }
        return HTTPResponse(status: 200, contentType: type, body: data)
    }
}
```

- [ ] **Step 4: GREEN gör**

Run: `swift test --filter RemoteRoutesTests`
Expected: 6 test PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentOfficeCore/RemoteRoutes.swift Tests/AgentOfficeCoreTests/RemoteRoutesTests.swift
git commit -m "Remote access: HTTP routes for pairing, sessions, transcripts and the web app files"
```

---

### Task 7: Sunucu (Network.framework)

**Files:**
- Create: `Sources/AgentOfficeCore/RemoteServer.swift`
- Test: `Tests/AgentOfficeCoreTests/RemoteServerTests.swift`

**Interfaces:**
- Consumes: Task 1, 2, 5, 6.
- Produces:
  - `public final class RemoteServer: @unchecked Sendable`
    - `public struct Handlers: Sendable { routes: RemoteRoutes; command: @Sendable (ClientMessage) async -> String?; welcome: @Sendable () async -> [ServerEvent]; init(...) }` — `command` başarıda nil, hatada kod (`not_running`, `invalid_text`) döner.
    - `init(handlers: Handlers)`
    - `func start(host: String, port: UInt16) async throws -> UInt16` (0 = sistem seçer; gerçek portu döner)
    - `func stop()`
    - `func broadcast(_ event: ServerEvent)` (yalnızca auth olmuş WebSocket'lere)
    - `func disconnect(deviceId: String)`
  - Kapanış kodları: 4401 (auth yok / geçersiz), 1002 (protokol hatası), 1003 (desteklenmeyen çerçeve).

- [ ] **Step 1: Başarısız testleri yaz**

```swift
import Foundation
import Testing
@testable import AgentOfficeCore

final class CommandLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ClientMessage] = []
    func add(_ message: ClientMessage) { lock.withLock { items.append(message) } }
    var all: [ClientMessage] { lock.withLock { items } }

    func wait(count: Int, timeout: TimeInterval = 2) async -> [ClientMessage] {
        let deadline = Date().addingTimeInterval(timeout)
        while all.count < count, Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        return all
    }
}

@Suite(.serialized) struct RemoteServerTests {
    struct Running {
        let server: RemoteServer
        let auth: RemoteAuth
        let port: UInt16
        let log: CommandLog
    }

    func startServer() async throws -> Running {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("remote-server-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("<h1>Slash</h1>".utf8).write(to: dir.appendingPathComponent("index.html"))
        let auth = RemoteAuth(fileURL: dir.appendingPathComponent("devices.json"))
        let log = CommandLog()
        let routes = RemoteRoutes(auth: auth, staticRoot: dir, sessions: { [] }, transcript: { _, _ in nil })
        let server = RemoteServer(handlers: .init(routes: routes,
                                                  command: { log.add($0); return nil },
                                                  welcome: { [.sessions([])] }))
        let port = try await server.start(host: "127.0.0.1", port: 0)
        return Running(server: server, auth: auth, port: port, log: log)
    }

    func socket(_ running: Running) -> URLSessionWebSocketTask {
        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(running.port)/api/stream")!)
        task.resume()
        return task
    }

    func receiveText(_ task: URLSessionWebSocketTask) async throws -> [String: Any] {
        guard case .string(let text) = try await task.receive() else { return [:] }
        return try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] ?? [:]
    }

    @Test func servesTheWebAppOverHTTP() async throws {
        let running = try await startServer()
        defer { running.server.stop() }
        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(running.port)/")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(data == Data("<h1>Slash</h1>".utf8))
    }

    @Test func apiWithoutTokenIs401() async throws {
        let running = try await startServer()
        defer { running.server.stop() }
        let (_, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(running.port)/api/sessions")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 401)
    }

    @Test func authenticatedSocketGetsReadyThenSessions() async throws {
        let running = try await startServer()
        defer { running.server.stop() }
        let token = try #require(running.auth.pair(code: running.auth.newPairingCode(), deviceName: "p"))
        let task = socket(running)
        try await task.send(.string(#"{"type":"auth","token":"\#(token)"}"#))
        #expect(try await receiveText(task)["type"] as? String == "ready")
        #expect(try await receiveText(task)["type"] as? String == "sessions")
        running.server.broadcast(.transcriptChanged(sessionId: "s1"))
        #expect(try await receiveText(task)["sessionId"] as? String == "s1")
        task.cancel(with: .goingAway, reason: nil)
    }

    @Test func commandsArriveInOrder() async throws {
        let running = try await startServer()
        defer { running.server.stop() }
        let token = try #require(running.auth.pair(code: running.auth.newPairingCode(), deviceName: "p"))
        let task = socket(running)
        try await task.send(.string(#"{"type":"auth","token":"\#(token)"}"#))
        _ = try await receiveText(task)
        for text in ["bir", "iki", "üç"] {
            try await task.send(.string(#"{"type":"send.text","sessionId":"s","text":"\#(text)"}"#))
        }
        let received = await running.log.wait(count: 3)
        #expect(received == ["bir", "iki", "üç"].map { .sendText(sessionId: "s", text: $0) })
        task.cancel(with: .goingAway, reason: nil)
    }

    @Test func messagesBeforeAuthCloseTheSocket() async throws {
        let running = try await startServer()
        defer { running.server.stop() }
        let task = socket(running)
        try await task.send(.string(#"{"type":"send.text","sessionId":"s","text":"rm"}"#))
        await #expect(throws: (any Error).self) { _ = try await task.receive() }
        #expect(running.log.all.isEmpty)

        let wrong = socket(running)
        try await wrong.send(.string(#"{"type":"auth","token":"nope"}"#))
        await #expect(throws: (any Error).self) { _ = try await wrong.receive() }
    }

    @Test func revokedDeviceIsDisconnected() async throws {
        let running = try await startServer()
        defer { running.server.stop() }
        let token = try #require(running.auth.pair(code: running.auth.newPairingCode(), deviceName: "p"))
        let device = try #require(running.auth.device(forToken: token))
        let task = socket(running)
        try await task.send(.string(#"{"type":"auth","token":"\#(token)"}"#))
        _ = try await receiveText(task)
        _ = try await receiveText(task)
        running.auth.revoke(device.id)
        running.server.disconnect(deviceId: device.id)
        await #expect(throws: (any Error).self) { _ = try await task.receive() }
    }
}
```

- [ ] **Step 2: RED gör**

Run: `swift test --filter RemoteServerTests`
Expected: derleme hatası (`RemoteServer` yok).

- [ ] **Step 3: Uygula**

```swift
import Foundation
import Network

/// Uzaktan erişim sunucusu (spec §2, §7): tek adres ve port, HTTP + WebSocket. Her bağlantının durumu tek seri
/// kuyrukta tutulur; uygulama verisi `Handlers` üzerinden async alınır.
public final class RemoteServer: @unchecked Sendable {
    public struct Handlers: Sendable {
        public var routes: RemoteRoutes
        /// WebSocket'ten gelen komut (auth hariç), geliş sırasıyla. Başarıda nil, hatada hata kodu.
        public var command: @Sendable (ClientMessage) async -> String?
        /// Kimliği doğrulanan yeni WebSocket'e `ready`'den sonra gönderilecek ilk olaylar.
        public var welcome: @Sendable () async -> [ServerEvent]

        public init(routes: RemoteRoutes, command: @escaping @Sendable (ClientMessage) async -> String?,
                    welcome: @escaping @Sendable () async -> [ServerEvent]) {
            self.routes = routes
            self.command = command
            self.welcome = welcome
        }
    }

    final class Client: @unchecked Sendable {
        let connection: NWConnection
        var buffer = Data()
        var isWebSocket = false
        var deviceId: String?

        init(connection: NWConnection) { self.connection = connection }
    }

    private final class Once: @unchecked Sendable {
        var done = false
    }

    private let handlers: Handlers
    private let queue = DispatchQueue(label: "agentoffice.remote")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    /// Komutlar sırayla işlenir (iki mesaj terminale ters sırada gitmesin).
    private var commandChain: Task<Void, Never>?

    public init(handlers: Handlers) {
        self.handlers = handlers
    }

    /// Yalnızca `host` adresinde dinler. `port` 0 ise sistem seçer; dinlemeye başlayınca gerçek portu döner.
    public func start(host: String, port: UInt16) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard !once.done else { return }
                    once.done = true
                    continuation.resume(returning: listener.port?.rawValue ?? port)
                case .failed(let error):
                    self?.stop()
                    guard !once.done else { return }
                    once.done = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            queue.async {
                self.listener = listener
                listener.start(queue: self.queue)
            }
        }
    }

    public func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            for client in self.clients.values { client.connection.cancel() }
            self.clients = [:]
        }
    }

    public func broadcast(_ event: ServerEvent) {
        let payload = event.jsonData()
        queue.async {
            for client in self.clients.values where client.deviceId != nil { self.sendFrame(client, .text, payload) }
        }
    }

    public func disconnect(deviceId: String) {
        queue.async {
            for client in self.clients.values where client.deviceId == deviceId { self.closeWebSocket(client, code: 4401) }
        }
    }

    // MARK: - Bağlantılar (hepsi `queue` üzerinde)

    private func accept(_ connection: NWConnection) {
        let client = Client(connection: connection)
        let key = ObjectIdentifier(client)
        clients[key] = client
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.clients.removeValue(forKey: key)
            default: break
            }
        }
        connection.start(queue: queue)
        receive(client)
    }

    private func receive(_ client: Client) {
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { client.buffer.append(data) }
            self.process(client)
            if isComplete || error != nil {
                client.connection.cancel()
                return
            }
            if self.clients[ObjectIdentifier(client)] != nil { self.receive(client) }
        }
    }

    private func process(_ client: Client) {
        if client.isWebSocket {
            processFrames(client)
            return
        }
        switch HTTPParser.parse(client.buffer) {
        case .incomplete:
            return
        case .invalid(let status):
            client.buffer = Data()
            respond(client, .error(status, "bad_request"))
        case .request(let request, let consumed):
            client.buffer = Data(client.buffer.dropFirst(consumed))
            if request.path == "/api/stream", request.isWebSocketUpgrade, let key = request.header("sec-websocket-key") {
                client.isWebSocket = true
                client.connection.send(content: WebSocket.handshake(key: key), completion: .contentProcessed { _ in })
                queue.asyncAfter(deadline: .now() + 10) { [weak self] in
                    if client.deviceId == nil { self?.closeWebSocket(client, code: 4401) }
                }
                // El sıkışmayla aynı pakette gelen çerçeve kaybolmasın.
                processFrames(client)
            } else {
                let routes = handlers.routes
                Task {
                    let response = await routes.respond(to: request)
                    self.queue.async { self.respond(client, response) }
                }
            }
        }
    }

    private func respond(_ client: Client, _ response: HTTPResponse) {
        client.connection.send(content: response.serialized(), completion: .contentProcessed { _ in client.connection.cancel() })
    }

    private func processFrames(_ client: Client) {
        while clients[ObjectIdentifier(client)] != nil {
            switch WebSocket.decode(client.buffer) {
            case .incomplete:
                return
            case .invalid:
                closeWebSocket(client, code: 1002)
                return
            case .frame(let frame, let consumed):
                client.buffer = Data(client.buffer.dropFirst(consumed))
                handle(frame, from: client)
            }
        }
    }

    private func handle(_ frame: WebSocket.Frame, from client: Client) {
        switch frame.opcode {
        case .ping: sendFrame(client, .pong, frame.payload)
        case .pong: break
        case .close: closeWebSocket(client, code: 1000)
        case .text: handleText(frame.payload, from: client)
        default: closeWebSocket(client, code: 1003)
        }
    }

    private func handleText(_ payload: Data, from client: Client) {
        guard let message = try? RemoteJSON.decoder().decode(ClientMessage.self, from: payload) else {
            if client.deviceId == nil { closeWebSocket(client, code: 4401) } else { sendFrame(client, .text, ServerEvent.error("bad_message").jsonData()) }
            return
        }
        if case .auth(let token) = message {
            guard client.deviceId == nil, let device = handlers.routes.auth.device(forToken: token) else {
                closeWebSocket(client, code: 4401)
                return
            }
            client.deviceId = device.id
            let welcome = handlers.welcome
            Task {
                let events = await welcome()
                self.queue.async {
                    self.sendFrame(client, .text, ServerEvent.ready.jsonData())
                    for event in events { self.sendFrame(client, .text, event.jsonData()) }
                }
            }
            return
        }
        guard client.deviceId != nil else {
            closeWebSocket(client, code: 4401)
            return
        }
        let command = handlers.command
        let previous = commandChain
        commandChain = Task {
            await previous?.value
            if let code = await command(message) {
                self.queue.async { self.sendFrame(client, .text, ServerEvent.error(code).jsonData()) }
            }
        }
    }

    private func sendFrame(_ client: Client, _ opcode: WebSocket.Opcode, _ payload: Data) {
        client.connection.send(content: WebSocket.encode(opcode, payload), completion: .contentProcessed { _ in })
    }

    private func closeWebSocket(_ client: Client, code: UInt16) {
        clients.removeValue(forKey: ObjectIdentifier(client))
        client.connection.send(content: WebSocket.encode(.close, WebSocket.closePayload(code: code)),
                               completion: .contentProcessed { _ in client.connection.cancel() })
    }
}
```

- [ ] **Step 4: GREEN gör**

Run: `swift test --filter RemoteServerTests`
Expected: 6 test PASS. (URLSession'ın düz HTTP'yi App Transport Security yüzünden reddettiği görülürse IP adresine yapılan bağlantılar ATS dışıdır; `localhost` kullanma, `127.0.0.1` kalsın.)

- [ ] **Step 5: Yalnızca seçilen adreste dinlendiğini doğrula**

Testleri `swift test --filter RemoteServerTests/servesTheWebAppOverHTTP` ile çalıştırırken başka bir terminalde:

Run: `lsof -nP -iTCP -sTCP:LISTEN | grep xctest`
Expected: `127.0.0.1:<port>`; `*:<port>` OLMAMALI. `*` görünürse `requiredLocalEndpoint` dinleyiciye uygulanmıyor demektir: `NWPathMonitor().currentPath.availableInterfaces` içinden adı eşleşen `NWInterface`'i bulup `parameters.requiredInterface`'e ver ve tekrar doğrula.

- [ ] **Step 6: Tüm paketi çalıştır**

Run: `swift test`
Expected: tüm testler PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentOfficeCore/RemoteServer.swift Tests/AgentOfficeCoreTests/RemoteServerTests.swift
git commit -m "Remote access: HTTP and WebSocket server bound to a single address"
```

---

### Task 8: Telefondan gelen metni terminale hazırlama

**Files:**
- Create: `Sources/AgentOfficeCore/RemoteInput.swift`
- Test: `Tests/AgentOfficeCoreTests/RemoteInputTests.swift`

**Interfaces:**
- Produces: `public enum RemoteInput { static let maxTextLength = 20_000; static let submit = "\r"; static let interrupt = "\u{1b}"; static func paste(_ text: String, bracketedPaste: Bool) -> String? }`

- [ ] **Step 1: Başarısız testleri yaz**

```swift
import Testing
@testable import AgentOfficeCore

@Suite struct RemoteInputTests {
    @Test func wrapsInBracketedPaste() {
        #expect(RemoteInput.paste("Testleri çalıştır 🚀", bracketedPaste: true) == "\u{1b}[200~Testleri çalıştır 🚀\u{1b}[201~")
    }

    @Test func keepsLinesAndNormalizesCRLF() {
        #expect(RemoteInput.paste("bir\r\niki\nüç", bracketedPaste: true) == "\u{1b}[200~bir\niki\nüç\u{1b}[201~")
    }

    @Test func escapeCannotLeavePaste() {
        let attack = "a\u{1b}[201~\r/exit\r\u{7}\u{9b}b"
        #expect(RemoteInput.paste(attack, bracketedPaste: true) == "\u{1b}[200~a[201~/exitb\u{1b}[201~")
    }

    @Test func withoutBracketedPasteNewlinesBecomeSpaces() {
        #expect(RemoteInput.paste("bir\niki", bracketedPaste: false) == "bir iki")
    }

    @Test func emptyOrHugeIsRefused() {
        #expect(RemoteInput.paste("  \n ", bracketedPaste: true) == nil)
        #expect(RemoteInput.paste(String(repeating: "a", count: RemoteInput.maxTextLength + 1), bracketedPaste: true) == nil)
    }
}
```

`escapeCannotLeavePaste` beklentisi: ESC (0x1B), CR, BEL (0x07) ve C1 kontrolü (0x9B) silinir; `\r` CRLF değilse satır sonu değildir ve atılır. Geriye `a[201~/exitb` kalır.

- [ ] **Step 2: RED gör**

Run: `swift test --filter RemoteInputTests`
Expected: derleme hatası.

- [ ] **Step 3: Uygula**

```swift
/// Telefondan gelen metin (spec §6): terminale yazmadan önce kontrol karakterleri atılır, böylece metin bracketed
/// paste'ten kaçıp tuş gönderemez. Satır sonları korunur; gönderme (`submit`) ayrıca yazılır.
public enum RemoteInput {
    public static let maxTextLength = 20_000
    public static let submit = "\r"
    public static let interrupt = "\u{1b}"

    public static func paste(_ text: String, bracketedPaste: Bool) -> String? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var scalars = String.UnicodeScalarView()
        for scalar in normalized.unicodeScalars where scalar == "\n" || scalar == "\t" || !isControl(scalar) {
            scalars.append(scalar)
        }
        let cleaned = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= maxTextLength else { return nil }
        guard bracketedPaste else { return cleaned.replacingOccurrences(of: "\n", with: " ") }
        return "\u{1b}[200~" + cleaned + "\u{1b}[201~"
    }

    static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || scalar.value == 0x7F || (0x80...0x9F).contains(scalar.value)
    }
}
```

- [ ] **Step 4: GREEN gör**

Run: `swift test --filter RemoteInputTests`
Expected: 5 test PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentOfficeCore/RemoteInput.swift Tests/AgentOfficeCoreTests/RemoteInputTests.swift
git commit -m "Remote access: sanitize phone text before it reaches the terminal"
```

---

### Task 9: Uygulama köprüsü (RemoteBridge) ve AppModel bağlantısı

**Files:**
- Create: `Sources/AgentOffice/RemoteBridge.swift`, `Sources/AgentOffice/AppModel+Remote.swift`
- Modify: `Sources/AgentOffice/AppModel.swift` (`transcriptPaths` görünürlüğü, `remote` özelliği, `start()`, `stop()`, `handle(_:)`)
- Modify: `Sources/AgentOffice/TranscriptWatcher.swift` (`onChange`)

**Interfaces:**
- Consumes: Task 1–8.
- Produces:
  - `@MainActor @Observable final class RemoteBridge` — `enum Status: Equatable { off, starting, running(url: String), noInterface, failed(String) }`; `status`, `pairingCode: String?`, `devices: [PairedDevice]`, `enabled: Bool`, `mode: RemoteMode`, `pairingURL: String?`; `attach(_ model: AppModel)`, `apply()`, `newPairingCode()`, `revoke(_ device: PairedDevice)`, `transcriptChanged(_ id: String)`, `stop()`. UserDefaults anahtarları: `remoteEnabled`, `remoteMode`, `remotePort`.
  - `AppModel.remote: RemoteBridge`
  - `AppModel.canSendRemotely(_ id: String) -> Bool`, `AppModel.remoteTranscriptPath(_ id: String) -> String?`, `AppModel.handleRemote(_ message: ClientMessage) -> String?`
  - `TranscriptWatcher.onChange: ((String) -> Void)?`

Bu task uygulama hedefinde (AppKit, SwiftTerm) olduğu için birim testi yok; doğrulama derleme, tüm paket testleri ve el ile uçtan uca denemedir (Task 12).

- [ ] **Step 1: TranscriptWatcher'a değişiklik bildirimi ekle**

`Sources/AgentOffice/TranscriptWatcher.swift` içinde `var onInterrupt` satırının altına:

```swift
    /// Kayıt dosyası değişti (en çok saniyede bir); telefon yeni mesajları çeker.
    var onChange: ((String) -> Void)?
```

`changed(_:)` içindeki `if interrupted { self.onInterrupt?(id) }` satırının hemen önüne:

```swift
            self.onChange?(id)
```

- [ ] **Step 2: AppModel'e köprüyü bağla**

`Sources/AgentOffice/AppModel.swift`:

1. `@ObservationIgnored private var transcriptPaths: [String: String] = [:]` → `@ObservationIgnored private(set) var transcriptPaths: [String: String] = [:]`
2. `let diffWatcher = DiffWatcher()` satırının altına:

```swift
    /// Telefondan erişim (spec: uzaktan erişim): ayara göre sunucuyu açar, oturumları telefona yayınlar.
    let remote = RemoteBridge()
```

3. `start()` içinde `transcriptWatcher.onInterrupt = …` satırının altına:

```swift
        transcriptWatcher.onChange = { [weak self] id in self?.remote.transcriptChanged(id) }
```

4. `start()` içinde, demo kontrolünden (`if ProcessInfo.processInfo.environment["AGENT_OFFICE_DEMO"] == "1"`) hemen önce:

```swift
        remote.attach(self)
```

5. `stop()` içinde `server?.stop()` satırının altına:

```swift
        remote.stop()
```

6. `handle(_:)` içinde `watchTranscript(envelope.session)` satırının altına (tur bitince izleme durur; son mesaj bu bildirimle gelir):

```swift
        remote.transcriptChanged(envelope.session)
```

- [ ] **Step 3: AppModel+Remote.swift'i yaz**

```swift
import AgentOfficeCore
import Foundation

extension AppModel {
    /// Telefondan mesaj gönderilebilir mi: oturum bu Mac'te bir panelde çalışıyor (arka plandaki ve durmuş oturumlar hayır).
    func canSendRemotely(_ id: String) -> Bool {
        terminals[id] != nil && isRunning(id) && store.session(id)?.state != .exited
    }

    func remoteTranscriptPath(_ id: String) -> String? { transcriptPaths[id] }

    /// Telefondan gelen komut. Başarıda nil, hatada telefonun çevireceği kod.
    func handleRemote(_ message: ClientMessage) -> String? {
        switch message {
        case .auth:
            return nil
        case .sendText(let id, let text):
            guard canSendRemotely(id), let terminal = terminals[id] else { return "not_running" }
            guard let paste = RemoteInput.paste(text, bracketedPaste: terminal.getTerminal().bracketedPasteMode) else {
                return "invalid_text"
            }
            DebugLog.write("remote text → \(id) (\(text.count) chars)")
            terminal.send(txt: paste)
            // Enter ayrı yazılır: yapıştırmayla aynı parçada gelirse yapıştırmanın içinde sayılabilir.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                terminal.send(txt: RemoteInput.submit)
            }
            return nil
        case .interrupt(let id):
            guard canSendRemotely(id), let terminal = terminals[id] else { return "not_running" }
            DebugLog.write("remote interrupt → \(id)")
            terminal.send(txt: RemoteInput.interrupt)
            return nil
        }
    }
}
```

- [ ] **Step 4: RemoteBridge.swift'i yaz**

```swift
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
        auth?.revoke(device.id)
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
```

- [ ] **Step 5: Derle ve tüm testleri çalıştır**

Run: `swift build && swift test`
Expected: derleme uyarısız (Swift 6 eşzamanlılık uyarıları dahil), tüm testler PASS. Bir `Sendable` uyarısı çıkarsa `@MainActor` kapanışı `await MainActor.run { … }` ile sarmala; mantığı değiştirme.

- [ ] **Step 6: Çalışmayan oturuma gönderme kontrolü (el ile)**

`swift run AgentOffice` ile aç, Task 12 tamamlanana kadar `defaults write io.github.egekolslash.slashoffice remoteEnabled -bool YES` ve `remoteMode localNetwork` (ya da Tailscale bağlıysa varsayılan) ile sunucuyu başlat. Durmuş bir oturumun kimliğiyle:

Run: Task 7 testlerindeki gibi bir WebSocket istemcisiyle (örneğin `websocat`) auth ol, `{"type":"send.text","sessionId":"<durmuş oturum>","text":"x"}` gönder.
Expected: `{"type":"error","code":"not_running"}` gelir, terminale hiçbir şey yazılmaz.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentOffice/RemoteBridge.swift Sources/AgentOffice/AppModel+Remote.swift \
        Sources/AgentOffice/AppModel.swift Sources/AgentOffice/TranscriptWatcher.swift
git commit -m "Remote access: bridge the store, transcripts and terminals to the server"
```

---

### Task 10: Ayarlar › Telefondan erişim

**Files:**
- Create: `Sources/AgentOffice/RemoteSettingsView.swift`
- Modify: `Sources/AgentOffice/SimpleOfficeView.swift` (`SettingsView`), `Sources/AgentOffice/AgentOfficeApp.swift:149`
- Modify: `Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `RemoteBridge` (Task 9).
- Produces: `struct RemoteSettingsSection: View { @Bindable var remote: RemoteBridge }`, `enum QRCode { static func image(for text: String) -> NSImage? }`, `SettingsView.remote: RemoteBridge?`.

- [ ] **Step 1: RemoteSettingsView.swift'i yaz**

```swift
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
```

- [ ] **Step 2: SettingsView'e bağla**

`Sources/AgentOffice/SimpleOfficeView.swift`, `SettingsView` içinde `var runningAgents: () -> Int = { 0 }` satırının altına:

```swift
    /// Telefondan erişim bölümü; önizlemelerde nil.
    var remote: RemoteBridge?
```

Aynı dosyada `Toggle("Energy saving", …)` açıklama `Text`'inin `.fixedSize(…)` satırından sonra, `Form`'un kapanışından önce:

```swift
            if let remote {
                Divider()
                RemoteSettingsSection(remote: remote)
            }
```

`Sources/AgentOffice/AgentOfficeApp.swift:149`:

```swift
        Settings { SettingsView(runningAgents: { [delegate] in delegate.model.runningAgentCount }, remote: delegate.model.remote) }
```

- [ ] **Step 3: Türkçe metinleri kataloğa ekle**

Run (worktree kökünde, betik scratchpad'de değil depodaki dosyayı düzenler):

```bash
python3 -I - Resources/Localizable.xcstrings <<'EOF'
import json, sys
path = sys.argv[1]
catalog = json.load(open(path, encoding="utf-8"))
entries = {
    "Phone access": "Telefondan erişim",
    "Follow your sessions from your phone, answer and write back. A paired phone can make Claude run anything on this Mac, so pair only your own devices.":
        "Oturumlarını telefondan takip et, cevap ver ve mesaj yaz. Eşleşmiş bir telefon bu Mac'te Claude'a her şeyi yaptırabilir; yalnızca kendi cihazlarını eşleştir.",
    "Network": "Ağ",
    "Local network": "Yerel ağ",
    "On the local network, traffic is not encrypted. Use it only on networks you trust.":
        "Yerel ağda trafik şifrelenmez. Yalnızca güvendiğin ağlarda kullan.",
    "Last seen %@": "Son görülme: %@",
    "Not connected yet": "Henüz bağlanmadı",
    "Revoke": "İptal et",
    "Starting…": "Başlatılıyor…",
    "Address": "Adres",
    "Tailscale is not connected on this Mac. Open Tailscale and sign in; the address appears here by itself.":
        "Bu Mac'te Tailscale bağlı değil. Tailscale'i açıp giriş yap; adres burada kendiliğinden görünür.",
    "This Mac is not on a local network.": "Bu Mac bir yerel ağa bağlı değil.",
    "Could not start: %@": "Başlatılamadı: %@",
    "Scan with your phone's camera.": "Telefonunun kamerasıyla okut.",
    "The code works once, for 2 minutes.": "Kod bir kez ve 2 dakika boyunca geçerli.",
    "Pair a Phone…": "Telefon eşleştir…",
}
for key, tr in entries.items():
    catalog["strings"].setdefault(key, {})["localizations"] = {"tr": {"stringUnit": {"state": "translated", "value": tr}}}
with open(path, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")
EOF
git diff --stat Resources/Localizable.xcstrings
```

Expected: yalnızca eklenen anahtarlar değişir. Diff başka satırları da yeniden biçimlendirdiyse (girinti, sıralama) dosyayı `git checkout Resources/Localizable.xcstrings` ile geri al ve anahtarları Xcode'un String Catalog düzenleyicisiyle ekle; amaç tek başına okunabilir bir diff.

- [ ] **Step 4: Yerelleştirme testlerini çalıştır**

Run: `swift test --filter LocalizationTests`
Expected: PASS (`catalogCoversSourceStrings` yeni metinleri katalogda bulur; `noTurkishLeftInSources` temiz).

- [ ] **Step 5: Ekranı gör**

Run: `swift build && swift run AgentOffice`, sonra ⌘, ile Ayarlar.
Expected: "Phone access" anahtarı kapalı. Açınca ağ seçici, adres ya da "Tailscale is not connected…" uyarısı, "Pair a Phone…" görünür. Düğmeye basınca QR ve 6 haneli kod çıkar, 2 dakika sonra düğme geri gelir.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentOffice/RemoteSettingsView.swift Sources/AgentOffice/SimpleOfficeView.swift \
        Sources/AgentOffice/AgentOfficeApp.swift Resources/Localizable.xcstrings
git commit -m "Remote access: Settings section with network choice, pairing QR and paired phones"
```

---

### Task 11: Telefon uygulaması (PWA)

**Files:**
- Create: `Resources/Remote/index.html`, `Resources/Remote/app.css`, `Resources/Remote/app.js`, `Resources/Remote/manifest.json`
- Modify: `scripts/make-app.sh` (Remote klasörünü pakete kopyala)

**Interfaces:**
- Consumes: HTTP uçları (Task 6), WebSocket olayları ve komutları (Task 1, 7).
- Produces: tarayıcıda çalışan telefon arayüzü. `localStorage` anahtarı `slashoffice.token`; sohbet ekranı adresi `#s=<oturum kimliği>`; eşleştirme adresi `#pair=<kod>`.

- [ ] **Step 1: index.html**

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="theme-color" content="#1a1a26">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <title>Slash Office</title>
  <link rel="manifest" href="manifest.json">
  <link rel="stylesheet" href="app.css">
</head>
<body>
  <div id="bar" class="bar" hidden></div>
  <main id="pair" class="view" hidden>
    <h1>Slash Office</h1>
    <p id="pair-warning"></p>
    <label><span id="pair-code-label"></span><input id="pair-code" inputmode="numeric" maxlength="6" autocomplete="one-time-code"></label>
    <label><span id="pair-name-label"></span><input id="pair-name" maxlength="40"></label>
    <button id="pair-button"></button>
    <p id="pair-error" class="error"></p>
  </main>
  <main id="list" class="view" hidden>
    <h1>Slash Office</h1>
    <ul id="sessions" class="sessions"></ul>
    <p id="empty" class="muted" hidden></p>
  </main>
  <main id="chat" class="view chat" hidden>
    <header class="chat-head">
      <button id="back" class="link"></button>
      <div><div id="chat-title" class="title"></div><div id="chat-status" class="muted"></div></div>
    </header>
    <details id="todos" class="todos" hidden><summary id="todos-summary"></summary><ul id="todo-list"></ul></details>
    <ol id="messages" class="messages"></ol>
    <form id="composer" class="composer">
      <textarea id="text" rows="1"></textarea>
      <button id="stop" type="button" class="secondary" hidden></button>
      <button id="send" type="submit"></button>
    </form>
    <p id="chat-error" class="error"></p>
  </main>
  <script src="app.js"></script>
</body>
</html>
```

- [ ] **Step 2: app.css**

```css
:root {
  --bg: #1a1a26; --card: #24243a; --text: #f2f2f7; --muted: #a0a0b4; --line: #34344e;
  --accent: #7c8cff; --orange: #ff9f43; --green: #3ecf8e; --red: #ff6b6b;
  color-scheme: dark;
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text); font: 16px/1.4 -apple-system, system-ui, sans-serif;
       padding: env(safe-area-inset-top) 16px env(safe-area-inset-bottom); }
h1 { font-size: 22px; margin: 16px 0; }
.view { max-width: 720px; margin: 0 auto; }
.muted { color: var(--muted); font-size: 14px; }
.error { color: var(--red); font-size: 14px; }
.bar { position: sticky; top: 0; z-index: 2; background: var(--orange); color: #000; text-align: center;
       font-size: 13px; padding: 4px; margin: 0 -16px; }
label { display: block; margin: 12px 0; }
label span { display: block; font-size: 14px; color: var(--muted); margin-bottom: 4px; }
input, textarea { width: 100%; font: inherit; color: var(--text); background: var(--card); border: 1px solid var(--line);
                  border-radius: 10px; padding: 10px 12px; }
button { font: inherit; border: 0; border-radius: 10px; padding: 10px 16px; background: var(--accent); color: #fff; }
button.secondary { background: var(--card); border: 1px solid var(--line); }
button:disabled { opacity: .4; }
button.link { background: none; color: var(--accent); padding: 8px 0; }
.sessions { list-style: none; padding: 0; margin: 0; }
.sessions li { background: var(--card); border-radius: 12px; padding: 12px; margin-bottom: 8px; display: flex; gap: 10px; align-items: center; }
.dot { width: 10px; height: 10px; border-radius: 50%; flex: none; background: var(--muted); }
.dot.working { background: var(--green); } .dot.permission, .dot.question { background: var(--orange); }
.dot.exited { background: var(--line); }
.sessions .name { font-weight: 600; }
.sessions .summary { color: var(--muted); font-size: 14px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.sessions .text { min-width: 0; flex: 1; }
.badge { font-size: 12px; padding: 2px 8px; border-radius: 99px; background: var(--line); white-space: nowrap; }
.badge.permission, .badge.question { background: var(--orange); color: #000; }
.chat { display: flex; flex-direction: column; min-height: calc(100vh - env(safe-area-inset-top) - env(safe-area-inset-bottom)); }
.chat-head { display: flex; gap: 12px; align-items: center; position: sticky; top: 0; background: var(--bg); padding: 4px 0; z-index: 1; }
.title { font-weight: 600; }
.todos { background: var(--card); border-radius: 10px; padding: 8px 12px; margin: 8px 0; font-size: 14px; }
.todos ul { margin: 6px 0 0; padding-left: 18px; }
.todos .done { text-decoration: line-through; color: var(--muted); }
.messages { list-style: none; padding: 0; margin: 8px 0; flex: 1; }
.messages li { margin: 8px 0; white-space: pre-wrap; word-wrap: break-word; }
.messages .user { background: var(--accent); color: #fff; border-radius: 14px 14px 4px 14px; padding: 8px 12px; margin-left: 15%; }
.messages .assistant { background: var(--card); border-radius: 14px 14px 14px 4px; padding: 8px 12px; margin-right: 8%; }
.messages .tool { color: var(--muted); font: 13px ui-monospace, monospace; padding: 0 4px; }
.composer { display: flex; gap: 8px; align-items: flex-end; position: sticky; bottom: 0; background: var(--bg); padding: 8px 0; }
.composer textarea { resize: none; max-height: 40vh; }
```

- [ ] **Step 3: manifest.json**

```json
{
  "name": "Slash Office",
  "short_name": "Slash Office",
  "start_url": "./",
  "display": "standalone",
  "background_color": "#1a1a26",
  "theme_color": "#1a1a26"
}
```

- [ ] **Step 4: app.js**

```js
"use strict";

// Metinler: telefonun dili Türkçeyse Türkçe, değilse İngilizce.
const STRINGS = {
  en: {
    pairWarning: "A paired phone can make Claude run anything on your Mac. Pair only your own phone.",
    code: "Code from Slash Office Settings", name: "Name for this phone", pair: "Pair",
    wrongCode: "Wrong or expired code. Create a new one in Settings.", offline: "Reconnecting…",
    empty: "No sessions. Start one in Slash Office.", back: "‹ Sessions", send: "Send", stop: "Stop",
    todos: "Todo list", placeholder: "Write to Claude…",
    not_running: "This session is not running in Slash Office on your Mac.", invalid_text: "The message is empty or too long.",
    bad_message: "The Mac did not understand that.", failed: "Could not load.",
    status: { starting: "Starting", idle: "Idle", working: "Working", permission: "Needs permission", question: "Asking", exited: "Stopped" },
    finished: "Done",
  },
  tr: {
    pairWarning: "Eşleşmiş bir telefon Mac'inde Claude'a her şeyi yaptırabilir. Yalnızca kendi telefonunu eşleştir.",
    code: "Slash Office Ayarlar'daki kod", name: "Bu telefonun adı", pair: "Eşleştir",
    wrongCode: "Kod yanlış ya da süresi dolmuş. Ayarlar'dan yeni kod oluştur.", offline: "Yeniden bağlanıyor…",
    empty: "Oturum yok. Slash Office'te bir oturum başlat.", back: "‹ Oturumlar", send: "Gönder", stop: "Durdur",
    todos: "Yapılacaklar", placeholder: "Claude'a yaz…",
    not_running: "Bu oturum Mac'teki Slash Office'te çalışmıyor.", invalid_text: "Mesaj boş ya da çok uzun.",
    bad_message: "Mac bunu anlamadı.", failed: "Yüklenemedi.",
    status: { starting: "Başlıyor", idle: "Boşta", working: "Çalışıyor", permission: "İzin bekliyor", question: "Soru soruyor", exited: "Durdu" },
    finished: "Bitti",
  },
};
const T = STRINGS[(navigator.language || "en").toLowerCase().startsWith("tr") ? "tr" : "en"];
const TOKEN_KEY = "slashoffice.token";
const $ = (id) => document.getElementById(id);

const state = {
  token: null, socket: null, connected: false, retry: 1000,
  sessions: [], current: null, cursor: null, seen: new Set(), loading: false,
};

function readToken() { try { return localStorage.getItem(TOKEN_KEY); } catch { return null; } }
function writeToken(value) {
  try { value ? localStorage.setItem(TOKEN_KEY, value) : localStorage.removeItem(TOKEN_KEY); } catch {}
}

function show(view) {
  for (const id of ["pair", "list", "chat"]) $(id).hidden = id !== view;
}

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

async function api(path) {
  const response = await fetch(path, { headers: { Authorization: `Bearer ${state.token}` }, cache: "no-store" });
  if (response.status === 401) { forget(); throw new Error("unauthorized"); }
  if (!response.ok) throw new Error(String(response.status));
  return response.json();
}

// Eşleştirme

function setupPairing(code) {
  $("pair-warning").textContent = T.pairWarning;
  $("pair-code-label").textContent = T.code;
  $("pair-name-label").textContent = T.name;
  $("pair-button").textContent = T.pair;
  $("pair-code").value = code || "";
  $("pair-name").value = /iPhone/.test(navigator.userAgent) ? "iPhone" : /Android/.test(navigator.userAgent) ? "Android" : "Phone";
  $("pair-error").textContent = "";
  show("pair");
}

$("pair-button").addEventListener("click", async () => {
  $("pair-error").textContent = "";
  const response = await fetch("/api/pair", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ code: $("pair-code").value.trim(), deviceName: $("pair-name").value }),
  }).catch(() => null);
  if (!response || !response.ok) { $("pair-error").textContent = T.wrongCode; return; }
  state.token = (await response.json()).token;
  writeToken(state.token);
  history.replaceState(null, "", location.pathname);
  start();
});

function forget() {
  writeToken(null);
  state.token = null;
  const socket = state.socket;
  state.socket = null;  // önce boşalt: onclose yeniden bağlanmasın
  if (socket) socket.close();
  setupPairing("");
}

// Canlı bağlantı

function connect() {
  const scheme = location.protocol === "https:" ? "wss" : "ws";
  const socket = new WebSocket(`${scheme}://${location.host}/api/stream`);
  state.socket = socket;
  socket.onopen = () => socket.send(JSON.stringify({ type: "auth", token: state.token }));
  socket.onmessage = (event) => receive(JSON.parse(event.data));
  socket.onclose = (event) => {
    if (state.socket !== socket) return;
    state.connected = false;
    renderBar();
    if (event.code === 4401) { forget(); return; }
    setTimeout(() => { if (state.socket === socket && state.token) connect(); }, state.retry);
    state.retry = Math.min(state.retry * 2, 10000);
  };
}

function receive(message) {
  switch (message.type) {
    case "ready":
      state.connected = true; state.retry = 1000; renderBar();
      if (state.current) loadMore();
      break;
    case "sessions":
      state.sessions = message.sessions; renderList(); renderChatHead();
      break;
    case "transcript.changed":
      if (message.sessionId === state.current) loadMore();
      break;
    case "error":
      $("chat-error").textContent = T[message.code] || message.code;
      break;
  }
}

function renderBar() {
  $("bar").hidden = state.connected || !state.token;
  $("bar").textContent = T.offline;
  const session = currentSession();
  $("send").disabled = !state.connected || !session || !session.canSend;
  $("stop").disabled = $("send").disabled;
}

// Oturum listesi

function renderList() {
  const list = $("sessions");
  list.replaceChildren();
  for (const session of state.sessions) {
    const item = el("li");
    item.append(el("span", `dot ${session.status}`));
    const text = el("div", "text");
    text.append(el("div", "name", session.title));
    const line = session.status === "permission" || session.status === "question" ? session.detail : session.summary;
    if (line) text.append(el("div", "summary", line));
    item.append(text);
    const badge = session.finishedUnseen && session.status === "idle" ? T.finished : T.status[session.status];
    item.append(el("span", `badge ${session.status}`, badge));
    item.addEventListener("click", () => { location.hash = `s=${encodeURIComponent(session.id)}`; });
    list.append(item);
  }
  $("empty").hidden = state.sessions.length > 0;
  $("empty").textContent = T.empty;
}

// Sohbet

function currentSession() { return state.sessions.find((s) => s.id === state.current); }

function renderChatHead() {
  const session = currentSession();
  if (!session) return;
  $("chat-title").textContent = session.title;
  $("chat-status").textContent = session.detail ? `${T.status[session.status]} · ${session.detail}` : T.status[session.status];
  $("stop").hidden = session.status !== "working";
  const todos = session.todos || [];
  $("todos").hidden = todos.length === 0;
  $("todos-summary").textContent = `${T.todos} (${todos.filter((t) => t.status === "done").length}/${todos.length})`;
  $("todo-list").replaceChildren(...todos.map((t) => el("li", t.status === "done" ? "done" : "", t.title)));
  renderBar();
}

function openChat(id) {
  state.current = id; state.cursor = null; state.seen = new Set();
  $("messages").replaceChildren();
  $("chat-error").textContent = "";
  $("back").textContent = T.back; $("send").textContent = T.send; $("stop").textContent = T.stop;
  $("text").placeholder = T.placeholder;
  show("chat");
  renderChatHead();
  loadMore();
}

async function loadMore() {
  if (state.loading || !state.current) return;
  state.loading = true;
  const id = state.current;
  try {
    const query = state.cursor === null ? "" : `?after=${state.cursor}`;
    const page = await api(`/api/sessions/${encodeURIComponent(id)}/transcript${query}`);
    if (id !== state.current) return;
    const nearBottom = window.innerHeight + window.scrollY >= document.body.scrollHeight - 80;
    for (const message of page.messages) {
      if (state.seen.has(message.id)) continue;
      state.seen.add(message.id);
      $("messages").append(el("li", message.role, message.text));
    }
    state.cursor = page.cursor;
    if (nearBottom || query === "") window.scrollTo(0, document.body.scrollHeight);
  } catch (error) {
    if (String(error.message) !== "404") $("chat-error").textContent = T.failed;
  } finally {
    state.loading = false;
  }
}

$("back").addEventListener("click", () => { location.hash = ""; });

$("composer").addEventListener("submit", (event) => {
  event.preventDefault();
  const text = $("text").value.trim();
  if (!text || !state.connected || !state.current) return;
  state.socket.send(JSON.stringify({ type: "send.text", sessionId: state.current, text }));
  $("text").value = "";
  $("chat-error").textContent = "";
});

$("stop").addEventListener("click", () => {
  if (state.connected && state.current) state.socket.send(JSON.stringify({ type: "interrupt", sessionId: state.current }));
});

$("text").addEventListener("input", () => {
  $("text").style.height = "auto";
  $("text").style.height = `${$("text").scrollHeight}px`;
});

// Yönlendirme

function route() {
  const hash = location.hash.slice(1);
  if (hash.startsWith("pair=")) { setupPairing(decodeURIComponent(hash.slice(5))); return; }
  if (!state.token) { setupPairing(""); return; }
  if (hash.startsWith("s=")) { openChat(decodeURIComponent(hash.slice(2))); return; }
  state.current = null;
  show("list");
  renderList();
}

function start() {
  state.token = readToken();
  route();
  if (state.token && !state.socket) connect();
}

window.addEventListener("hashchange", route);
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && state.token && !state.connected) {
    const socket = state.socket;
    state.socket = null;  // eski bağlantının onclose'u yeniden bağlanmasın
    if (socket) socket.close();
    connect();
  }
});
start();
```

- [ ] **Step 5: Paketle**

`scripts/make-app.sh` içinde `cp Resources/packs.json …` satırının altına:

```sh
# Telefondan erişimin web uygulaması (RemoteServer sunar).
cp -R Resources/Remote "$STAGE/Contents/Resources/Remote"
```

- [ ] **Step 6: Masaüstü tarayıcıda dene**

Tailscale bağlıysa varsayılan modla, değilse `defaults write io.github.egekolslash.slashoffice remoteMode localNetwork` ile:

Run: `swift run AgentOffice`; Ayarlar › Phone access aç, "Pair a Phone…"; adres + `/#pair=<kod>` URL'sini Mac'teki Safari'de aç.
Expected: eşleştirme ekranı kod dolu gelir; "Pair" sonrası oturum listesi görünür; bir oturuma girince son mesajlar yüklenir; Mac'te o oturuma bir şey yazınca mesajlar 1–2 sn içinde telefona da düşer.

- [ ] **Step 7: Commit**

```bash
git add Resources/Remote scripts/make-app.sh
git commit -m "Remote access: the phone web app (pairing, session list, live chat, send and stop)"
```

---

### Task 12: İzinler, belgeler ve uçtan uca doğrulama

**Files:**
- Modify: `Resources/Info.plist`, `Resources/tr.lproj/InfoPlist.strings`, `README.md`

- [ ] **Step 1: Yerel ağ izni açıklaması**

`Resources/Info.plist`, `NSMicrophoneUsageDescription` satırının altına:

```xml
    <key>NSLocalNetworkUsageDescription</key><string>Slash Office uses the local network only when Phone access is on, so your phone can connect to it.</string>
```

`Resources/tr.lproj/InfoPlist.strings` sonuna:

```
"NSLocalNetworkUsageDescription" = "Slash Office yerel ağı yalnızca Telefondan erişim açıkken, telefonun bağlanabilmesi için kullanır.";
```

- [ ] **Step 2: README**

`README.md` › "What it does" listesine, "Review" maddesinin altına:

```markdown
- **Phone access** (off by default) — follow your sessions from your phone, read the conversation live, write to Claude and stop a turn. Your phone connects to Slash Office directly over [Tailscale](https://tailscale.com) or your local network; nothing goes through a server of ours. Pair a phone in **Settings › Phone access**.
```

"Lightweight by design" altındaki "No background daemons, analytics or network calls of its own" maddesini şununla değiştir:

```markdown
- No background daemons, analytics or network calls of its own. With **Phone access** on, Slash Office listens on your Tailscale or local network address only, and only paired phones can use it.
```

- [ ] **Step 3: Tüm testler ve paket**

Run: `swift test && scripts/make-app.sh`
Expected: tüm testler PASS; `build/SlashOffice.app` oluşur ve `build/SlashOffice.app/Contents/Resources/Remote/index.html` vardır.

- [ ] **Step 4: Telefonla uçtan uca (Tailscale)**

1. Mac ve telefonda Tailscale aynı hesapla açık.
2. `open build/SlashOffice.app`; Ayarlar › Phone access aç (mod Tailscale). Adres `http://100.x.y.z:47821` görünmeli. macOS gelen bağlantı onayı sorarsa izin ver.
3. Başka bir terminalde: `lsof -nP -iTCP:47821 -sTCP:LISTEN` → yalnızca `100.x.y.z:47821`.
4. "Pair a Phone…" → telefon kamerasıyla QR'ı okut → Safari'de eşleştir. Paylaş › Ana Ekrana Ekle.
5. Mac'te bir Claude oturumu başlat ve bir görev ver. Telefonda: liste durumu ≤ 1 sn'de "Çalışıyor" olur; sohbette tool satırları ve cevap akar.
6. Telefondan "Testleri listele" yaz → Mac terminalinde aynı mesaj gönderilmiş görünür; Türkçe karakterler ve çok satırlı metin bozulmaz.
7. Uzun bir iş sırasında telefonda "Durdur" → Mac'te tur kesilir, durum "Boşta" olur.
8. Mac'te oturumu kapat (durdu) → telefonda Gönder pasifleşir.
9. Ayarlar'da cihazı "Revoke" → telefon hemen eşleştirme ekranına düşer.
10. Tailscale'i Mac'te kapat → ≤ 10 sn'de ayarlarda "Tailscale is not connected…"; açınca adres geri gelir, telefon kendiliğinden yeniden bağlanır.
11. Ayarı kapat → `lsof` boş.

Expected: 11 adımın hepsi tutar. Tutmayan adımı not al ve ilgili task'a dönüp düzelt; düzeltme testle başlar.

- [ ] **Step 5: Commit**

```bash
git add Resources/Info.plist Resources/tr.lproj/InfoPlist.strings README.md
git commit -m "Remote access: local network permission text and README"
```
