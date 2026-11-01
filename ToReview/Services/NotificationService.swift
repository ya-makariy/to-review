import AppKit
import ToReviewCore
import UserNotifications

/// Posts "new PR waiting for review" notifications and opens the PR when one is clicked.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let model: AppModel
    private let center = UNUserNotificationCenter.current()

    init(model: AppModel) {
        self.model = model
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        guard model.settings.notificationsEnabled else { return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error { SharedStorage.log.error("Notification auth failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func notify(about prs: [PullRequest]) {
        for pr in prs.prefix(5) {
            let content = UNMutableNotificationContent()
            content.title = "Review requested: \(pr.shortReference)"
            content.body = pr.title
            content.subtitle = "by \(pr.author.displayName)"
            content.sound = .default
            content.userInfo = ["url": pr.url.absoluteString]
            let request = UNNotificationRequest(identifier: pr.id.description, content: content, trigger: nil)
            center.add(request)
        }
        if prs.count > 5 {
            let content = UNMutableNotificationContent()
            content.title = "\(prs.count - 5) more pull requests need your review"
            center.add(UNNotificationRequest(identifier: "overflow-\(Date().timeIntervalSince1970)", content: content, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let string = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: string) else { return }
        await MainActor.run { NSWorkspace.shared.open(url) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
