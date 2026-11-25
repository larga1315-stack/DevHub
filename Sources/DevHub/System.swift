import Foundation
import AppKit
import ServiceManagement
import UserNotifications

/// True when running from DevHub.app (not `swift run` / Xcode's bare executable).
/// Notifications and login items only work for a real app bundle.
var isAppBundle: Bool {
    Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
}

// MARK: - Notifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    // Show banners even though DevHub is the "active" app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

enum Notifier {
    static func setUp() {
        guard isAppBundle else { return }
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    static func send(title: String, body: String) {
        guard isAppBundle else { return }   // UNUserNotificationCenter crashes without a bundle
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

// MARK: - Launch at login

enum LoginItem {
    static var isSupported: Bool { isAppBundle }

    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static var statusText: String {
        switch status {
        case .enabled: return "פעיל"
        case .requiresApproval: return "ממתין לאישור ב-System Settings → General → Login Items"
        case .notRegistered: return "כבוי"
        case .notFound: return "לא נמצא (התקן את DevHub ב-Applications)"
        @unknown default: return ""
        }
    }
}
