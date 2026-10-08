import AppKit
import AVFoundation
import CoreGraphics
import SwiftUI
import UserNotifications

/// Agents > Permissions… ile açılan izin ekranı (rehberde de aynı liste): macOS pencereleri çalışma sırasında
/// tek tek çıkmasın diye hepsi başta istenir.
struct PermissionsView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions").font(.title2.bold())
            Text("Agents work in your folders. Grant permissions now so macOS doesn't ask one by one while they work.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PermissionsList()
            HStack {
                Spacer()
                Button("OK", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

/// İzin satırları ve durumları; Ayarlar'dan dönünce yenilenir.
struct PermissionsList: View {
    @State private var notifications: PermissionStatus = .unknown
    @State private var microphone: PermissionStatus = .unknown
    @State private var fullDisk: PermissionStatus = .unknown
    @State private var screen: PermissionStatus = .unknown

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            PermissionRow(title: "Full Disk Access", symbol: "internaldrive",
                          detail: "Removes the repeated file access prompts for Documents, Desktop, Downloads and other apps' data. Turn on Slash Office in System Settings, then restart the app.",
                          status: fullDisk, action: "Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            PermissionRow(title: "Notifications", symbol: "bell.badge",
                          detail: "Lets you know when an agent asks a question or waits for permission.",
                          status: notifications, action: "Allow") {
                if notifications == .denied {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                } else {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                        Task { @MainActor in await refresh() }
                    }
                }
            }
            PermissionRow(title: "Microphone", symbol: "mic",
                          detail: "For Claude Code's voice mode.",
                          status: microphone, action: "Allow") {
                if microphone == .denied {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                } else {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in Task { @MainActor in await refresh() } }
                }
            }
            PermissionRow(title: "Screen Recording", symbol: "rectangle.dashed.badge.record",
                          detail: "Lets agents in terminals take screenshots (for example to check a user interface). Restart the app after allowing.",
                          status: screen, action: "Allow") {
                // İlk istekte macOS kendi penceresini gösterir; sonrakilerde sadece Ayarlar'dan açılabilir.
                if !CGRequestScreenCaptureAccess() {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
                Task { await refresh() }
            }
        }
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
    let title: LocalizedStringKey
    let symbol: String
    let detail: LocalizedStringKey
    let status: PermissionStatus
    let action: LocalizedStringKey
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
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.titleAndIcon)
            case .unknown:
                EmptyView()
            case .notDetermined, .denied:
                Button(status == .denied ? "Open System Settings" : action, action: perform)
            }
        }
    }
}
