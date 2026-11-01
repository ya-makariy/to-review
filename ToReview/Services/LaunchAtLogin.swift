import ServiceManagement
import ToReviewCore

enum LaunchAtLogin {
    static func apply(enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            SharedStorage.log.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
