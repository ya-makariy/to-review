import AppKit
import SwiftUI
import ToReviewCore

/// Owns the `NSStatusItem`, its SwiftUI label and the popover.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let windows: WindowManager
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var hostingView: NSHostingView<StatusBarLabel>!

    init(model: AppModel, windows: WindowManager) {
        self.model = model
        self.windows = windows
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let label = StatusBarLabel(model: model) { [weak self] width in
            self?.statusItem.length = width
        }
        hostingView = NSHostingView(rootView: label)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        if let button = statusItem.button {
            button.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: button.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "ToReview"
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(windows: windows).environment(model))
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            model.markAllSeen()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let refresh = NSMenuItem(title: "Refresh now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open ToReview", action: #selector(WindowManager.showMainAction(_:)), keyEquivalent: "")
        open.target = windows
        menu.addItem(open)
        let settings = NSMenuItem(title: "Settings…", action: #selector(WindowManager.showSettingsAction(_:)), keyEquivalent: ",")
        settings.target = windows
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ToReview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // restore click handling for next time
    }

    @objc private func refreshNow() {
        Task { await model.refresh() }
    }
}
