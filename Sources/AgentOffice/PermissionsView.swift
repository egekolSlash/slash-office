import AppKit
import AVFoundation
import CoreGraphics
import SwiftUI
import UserNotifications

/// İlk açılışta (ve Ajanlar > İzinler… ile) gösterilen izin ekranı: macOS pencereleri çalışma sırasında
/// tek tek çıkmasın diye hepsi başta istenir.
struct PermissionsView: View {
    let onDone: () -> Void
    @State private var notifications: PermissionStatus = .unknown
    @State private var microphone: PermissionStatus = .unknown
    @State private var fullDisk: PermissionStatus = .unknown
    @State private var screen: PermissionStatus = .unknown

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("İzinler").font(.title2.bold())
            Text("Ajanlar senin klasörlerinde çalışıyor. macOS'un çalışma sırasında tek tek sormaması için izinleri şimdi ver.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PermissionRow(title: "Tam Disk Erişimi", symbol: "internaldrive",
                          detail: "Belgeler, Masaüstü, İndirilenler ve diğer uygulamaların verileri için tekrar tekrar çıkan dosya erişimi pencerelerini kaldırır. Ayarlar'da Slash Office'i aç; sonra uygulamayı yeniden başlat.",
                          status: fullDisk, action: "Ayarlar'ı aç") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            PermissionRow(title: "Bildirimler", symbol: "bell.badge",
                          detail: "Bir ajan soru sorduğunda ya da izin beklediğinde haber verir.",
                          status: notifications, action: "İzin ver") {
                if notifications == .denied {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                } else {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                        Task { @MainActor in await refresh() }
                    }
                }
            }
            PermissionRow(title: "Mikrofon", symbol: "mic",
                          detail: "Claude Code'un ses modu için.",
                          status: microphone, action: "İzin ver") {
                if microphone == .denied {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                } else {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in Task { @MainActor in await refresh() } }
                }
            }
            PermissionRow(title: "Ekran Kaydı", symbol: "rectangle.dashed.badge.record",
                          detail: "Terminallerdeki ajanlar ekran görüntüsü alabilsin (ör. bir arayüzü kontrol etmek için). İzin verdikten sonra uygulamayı yeniden başlat.",
                          status: screen, action: "İzin ver") {
                // İlk istekte macOS kendi penceresini gösterir; sonrakilerde sadece Ayarlar'dan açılabilir.
                if !CGRequestScreenCaptureAccess() {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
                Task { await refresh() }
            }

            HStack {
                Spacer()
                Button("Tamam", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .task { await refresh() }
        // Ayarlar'dan dönünce durum güncellensin.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        fullDisk = Self.hasFullDiskAccess ? .granted : .notDetermined
        screen = CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        microphone = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
        guard Notifier.canNotify else { notifications = .unknown; return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifications = switch settings.authorizationStatus {
        case .authorized, .provisional: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// TCC veritabanının klasörü yalnızca Tam Disk Erişimi olan süreçlere açılır.
    static var hasFullDiskAccess: Bool {
        let path = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC"
        return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }
}

enum PermissionStatus {
    case unknown, notDetermined, granted, denied
}

private struct PermissionRow: View {
    let title: String
    let symbol: String
    let detail: String
    let status: PermissionStatus
    let action: String
    let perform: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            switch status {
            case .granted:
                Label("Verildi", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.titleAndIcon)
            case .unknown:
                EmptyView()
            case .notDetermined, .denied:
                Button(status == .denied ? "Ayarlar'ı aç" : action, action: perform)
            }
        }
    }
}
