import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only. In the .app bundle LSUIElement does this too; needed for `swift run`.
        NSApp.setActivationPolicy(.accessory)
        Notifier.setUp()
    }
}

@main
struct DevHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var hub = Hub()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environmentObject(hub)
        } label: {
            Image(systemName: menuIcon)
        }
        .menuBarExtraStyle(.window)

        Window("פרויקט", id: WindowID.editor) {
            ProjectEditor().environmentObject(hub)
        }
        .windowResizability(.contentSize)

        Window("לוגים", id: WindowID.logs) {
            LogsWindow().environmentObject(hub)
        }
        .defaultSize(width: 860, height: 540)

        Window("בדיקת תיקון", id: WindowID.review) {
            FixReviewWindow().environmentObject(hub)
        }
        .defaultSize(width: 900, height: 640)

        Window("היסטוריית קריסות", id: WindowID.history) {
            HistoryWindow().environmentObject(hub)
        }
        .defaultSize(width: 720, height: 520)

        Window("הגדרות DevHub", id: WindowID.settings) {
            SettingsWindow().environmentObject(hub)
        }
        .windowResizability(.contentSize)
    }

    private var menuIcon: String {
        if hub.hasCrash { return "exclamationmark.triangle.fill" }
        if hub.fixes.values.contains(where: { $0.phase.isBusy }) { return "wand.and.stars" }
        return hub.anyRunning ? "hammer.circle.fill" : "hammer.fill"
    }
}

enum WindowID {
    static let editor = "editor"
    static let logs = "logs"
    static let review = "review"
    static let history = "history"
    static let settings = "settings"
}
