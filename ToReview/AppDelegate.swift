import AppKit
import ToReviewCore
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: AppModel!
    private var statusItem: StatusItemController!
    private var windows: WindowManager!
    private var notifications: NotificationService!

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        windows = WindowManager(model: model)
        notifications = NotificationService(model: model)
        statusItem = StatusItemController(model: model, windows: windows)
        MainMenu.install(windows: windows)

        model.onNewIncoming = { [notifications] prs in
            notifications?.notify(about: prs)
        }
        model.openSettings = { [windows] in windows?.showSettings() }
        notifications.requestAuthorizationIfNeeded()
        LaunchAtLogin.apply(enabled: model.settings.launchAtLogin)

        model.startPolling()
        if model.accounts.isEmpty {
            windows.showMain()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showMain()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopPolling()
    }
}
