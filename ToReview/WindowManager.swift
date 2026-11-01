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
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: nil)
    }

    // MARK: Activation policy
    //
    // An LSUIElement app has no menu bar of its own, so while one of our windows is open
    // we switch to `.regular` (menu bar + Dock icon) and go back to `.accessory` when the
    // last window closes, otherwise the previous app's menu stays visible.

    private var ownWindows: [NSWindow] { [mainWindow, settingsWindow].compactMap { $0 } }

    private func becomeRegular() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, ownWindows.contains(closing) else { return }
        // Other own windows still visible? Keep the menu bar.
        let remaining = ownWindows.filter { $0 !== closing && $0.isVisible }
        if remaining.isEmpty {
            // Sheets attached to the closing window report through the same notification
            // slightly later; defer so the policy flips after the window is really gone.
            DispatchQueue.main.async {
                if self.ownWindows.allSatisfy({ !$0.isVisible }) {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
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
        becomeRegular()
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
        becomeRegular()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showSettingsAction(_ sender: Any?) { showSettings() }
    @objc func showMainAction(_ sender: Any?) { showMain() }
}
