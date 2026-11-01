import AppKit
import SwiftUI
import ToReviewCore

/// Creates and reuses the main and settings windows. SwiftUI toolbars are bridged
/// through `sceneBridgingOptions`, so the window chrome is native Tahoe glass.
@MainActor
final class WindowManager: NSObject {
    private let model: AppModel
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func showMain() {
        if mainWindow == nil {
            let controller = NSHostingController(rootView: MainView().environment(model))
            controller.sceneBridgingOptions = [.toolbars, .title]
            let window = NSWindow(contentViewController: controller)
            window.title = "ToReview"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 980, height: 640))
            window.minSize = NSSize(width: 720, height: 420)
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("MainWindow")
            window.identifier = NSUserInterfaceItemIdentifier("main")
            mainWindow = window
        }
        model.markAllSeen()
        NSApp.activate()
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        if settingsWindow == nil {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            for pane in SettingsPane.allCases {
                let host = NSHostingController(rootView: pane.view().environment(model))
                host.preferredContentSize = NSSize(width: 540, height: 420)
                let item = NSTabViewItem(viewController: host)
                item.label = pane.title
                item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
                tabs.addTabViewItem(item)
            }
            let window = NSWindow(contentViewController: tabs)
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("SettingsWindow")
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showSettingsAction(_ sender: Any?) { showSettings() }
    @objc func showMainAction(_ sender: Any?) { showMain() }
}
