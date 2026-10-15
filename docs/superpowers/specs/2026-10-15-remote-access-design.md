# Telefondan Uzaktan Erişim — Tasarım

Canlı doküman: https://claude.ai/code/artifact/f4b0bcea-5fd2-49ac-80ea-17c2bfac6215 (bu dosya onun 2026-10-15 kopyasıdır).

Slash Office, Mac'te çalışan Claude Code oturumlarını telefondan izlemeyi, sorulara ve izin isteklerine cevap vermeyi ve mesaj yazmayı sağlayan, varsayılan olarak kapalı bir uzaktan erişim özelliği kazanır. Uygulama kendi içinde küçük bir HTTP ve WebSocket sunucusu açar; telefon buna Tailscale (önerilen), yerel ağ ya da kullanıcının seçtiği başka bir ağ üzerinden bağlanır.

## §1 Kapsam

Telefondan: oturum listesi ve durumları (bekleyenler üstte); bir oturumun konuşmasını canlı izleme (kullanıcı/Claude mesajları, tek satırlık tool özetleri, todo); izin ver/reddet; AskUserQuestion seçimi (çoklu seçim, "Diğer"); serbest mesaj ve Durdur (Esc).

Bu sürümde yok: oturum başlatma/kapatma, terminalin birebir görüntüsü, diff/dosya önizleme, Mac uyurken erişim, App Store uygulaması (telefon tarafı Mac'ten sunulan bir PWA).

## §2 Mimari

Claude Code oturumları Mac uygulamasını iki yoldan besler: hook olayları (`agent-office-hook` → `HookServer` → `AgentStore`) ve transkript dosyası (JSONL). Yeni parçalar: `TranscriptReader` (JSONL → sohbet mesajları, kaldığı bayttan devam), `RemoteBridge` (durum + mesajları yayınlar, terminale metin/tuş yazar), `RemoteServer` (HTTP + WebSocket, PWA dosyalarını sunar). Telefon: oturum listesi, sohbet, bekleme kartı.

## §3 Bağlantı modları

Sunucu Tailscale'e bağlı değildir: seçilen moda göre tek bir arayüzü dinler, her istekte cihaz token'ını kontrol eder. Hiçbir modda `0.0.0.0` dinlenmez.

| Mod | Dinlenen adres | Ev dışından | HTTPS/push |
| --- | --- | --- | --- |
| Tailscale (varsayılan) | Mac'in 100.64.0.0/10 adresi | Evet | `tailscale serve` ile |
| Yerel ağ | Wi-Fi/Ethernet adresi, `mac-adi.local` | Hayır | Yok (düz HTTP) |
| Özel ağ | Kullanıcının seçtiği arayüz | Evet | VPN'e bağlı |
| Tünel | 127.0.0.1; dışarıya kullanıcının tüneli | Evet | Tünel sağlar |

## §4 Eşleştirme ve güvenlik

1. Ayarlar › Telefondan erişim; varsayılan kapalı.
2. Mac QR gösterir: adres + tek kullanımlık 6 haneli kod; 2 dk geçerli, 5 yanlış denemede yenilenir.
3. Telefon kodu gönderir, 256 bitlik cihaz token'ı alır. Mac yalnızca token'ın hash'ini saklar.
4. HTTP: `Authorization: Bearer <token>`; WebSocket: token ilk mesajda, gelmezse bağlantı kapanır.
5. Eşleşmiş cihazlar listelenir, tek tıkla iptal; açık bağlantıları hemen kopar.

Riskler: transkriptler sır içerebilir; terminale yazmak Claude'a komut çalıştırtmaktır (eşleştirme ekranı söyler); yerel ağ modu şifresizdir (uyarı); macOS Yerel Ağ / güvenlik duvarı onayı istenebilir; README gizlilik ifadesi "özellik kapalıyken" diye güncellenir.

## §5 Telefon ekranları

1. Eşleştirme (QR'dan adres + kod; cihaz adı; yetki uyarısı).
2. Oturum listesi: proje başlığı, durum rozeti, iş özeti, zaman. Sıra: izin bekleyen, soru soran, çalışan, biten, durmuş.
3. Oturum sohbeti: balonlar; tool çağrıları tek gri satır; todo şeridi; altta mesaj alanı, Gönder, Durdur.
4. Bekleme kartı: izin (tool + komut; İzin ver/Reddet) ya da soru (seçenekler, onay kutuları, "Diğer").

Üstte bağlantı şeridi: Bağlı / Yeniden bağlanıyor; kopunca durum gri, gönderme kilitli.

## §6 Cevap akışları

- Serbest metin: bracketed paste + `\r`; Durdur: `ESC`.
- AskUserQuestion: `PreToolUse.tool_input.questions` tamamı okunur; seçimler tuş vuruşlarına çevrilir (`QuestionKeys`, test edilir); hook ile cevap mümkünse o tercih edilir.
- İzin: `PermissionRequest` hook'u her zaman eklenir, `agent-office-hook claude --wait`, ~130 sn zaman aşımı. Uzaktan erişim kapalı / telefon yok / kullanıcı son 60 sn'de Mac'te aktifse hemen "pas". 120 sn'de cevap yoksa "pas". Uygulama yoksa hook hemen 0 döner.

## §7 Protokol

HTTP: `GET /` (PWA), `POST /api/pair`, `GET /api/sessions`, `GET /api/sessions/{id}/transcript?after={cursor}`, `GET /api/stream` (WebSocket).
WS Mac→telefon: `session.updated`, `session.removed`, `transcript.appended`, `input.requested`, `input.resolved`.
WS telefon→Mac: `auth`, `send.text`, `interrupt`, `answer.question`, `answer.permission`. Bir `requestId` yalnızca bir kez cevaplanır.

## §8 Aşamalar

1. Salt okuma (sunucu, eşleştirme, Tailscale + yerel ağ, liste, sohbet) — durum değişikliği telefonda ≤ 1 sn; iptal edilen cihaz hemen kopar.
2. Yazma (serbest metin, Durdur) — Türkçe karakter ve çok satır bozulmaz.
3. Sorular (AskUserQuestion kartı, tuş çevirisi).
4. İzinler (`PermissionRequest`, `--wait`).
5. Bildirimler ve HTTPS (`tailscale serve`, web push).
6. Özel ağ ve tünel modları.
