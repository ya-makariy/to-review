import AppKit

/// Pure AppKit entry point: a menu-bar app has no SwiftUI scenes to bootstrap,
/// so we own the run loop and create windows on demand.
@main
@MainActor
enum AppMain {
    /// Retained for the process lifetime; `NSApplication.delegate` is weak.
    private static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // LSUIElement: no Dock icon
        app.run()
    }
}
