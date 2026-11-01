import ToReviewCore
import WidgetKit

struct ReviewEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot
    let fields: DisplayFields
    let mode: WidgetMode
    /// Accounts shown: all, or the one from config / paging.
    let scope: [AccountSnapshot]
    let scopeTitle: String
    /// Non-nil when ‹ › paging applies (no fixed account in config).
    let page: (index: Int, count: Int)?
    let isPlaceholder: Bool

    var incoming: [PullRequest] { scope.flatMap(\.incoming).sorted { $0.updatedAt > $1.updatedAt } }
    var outgoing: [PullRequest] { scope.flatMap(\.outgoing).sorted { $0.updatedAt > $1.updatedAt } }
    var hasUnseen: Bool { scope.contains { $0.hasUnseen } }
    var hasProblems: Bool { scope.contains { !$0.status.isHealthy && $0.status != .neverSynced } }
    var lastSuccess: Date? { scope.compactMap(\.status.lastSuccess).max() }

    /// Data older than 30 minutes probably means the app isn't running.
    var isStale: Bool {
        guard let lastSuccess else { return !isPlaceholder && snapshot.accounts.isEmpty == false }
        return Date().timeIntervalSince(lastSuccess) > 30 * 60
    }
}

struct SnapshotTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ReviewEntry {
        ReviewEntry.sample(mode: .incomingAndOutgoing)
    }

    func snapshot(for configuration: WidgetConfigIntent, in context: Context) async -> ReviewEntry {
        if context.isPreview { return ReviewEntry.sample(mode: configuration.mode) }
        return load(configuration)
    }

    func timeline(for configuration: WidgetConfigIntent, in context: Context) async -> Timeline<ReviewEntry> {
        let entry = load(configuration)
        // The app pushes reloads after every sync; this is just a safety net for relative times.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func load(_ configuration: WidgetConfigIntent) -> ReviewEntry {
        let settings = SettingsStore().loadSettings()
        let snapshot = SnapshotStore().load()
        let enabled = snapshot.accounts.filter(\.account.isEnabled)
        SharedStorage.log.notice("Widget timeline: \(snapshot.accounts.count) accounts, generated \(snapshot.generatedAt, privacy: .public)")

        if let picked = configuration.account, let snap = enabled.first(where: { $0.account.id == picked.id }) {
            return ReviewEntry(date: Date(), snapshot: snapshot, fields: settings.widgetFields, mode: configuration.mode,
                               scope: [snap], scopeTitle: snap.account.title, page: nil, isPlaceholder: false)
        }

        let pageCount = enabled.isEmpty ? 0 : enabled.count + 1
        let index = pageCount > 0 ? min(WidgetPaging.currentIndex(), pageCount - 1) : 0
        let scope: [AccountSnapshot] = index == 0 ? enabled : [enabled[index - 1]]
        let title = index == 0 ? "All accounts" : enabled[index - 1].account.title
        return ReviewEntry(date: Date(), snapshot: snapshot, fields: settings.widgetFields, mode: configuration.mode,
                           scope: scope, scopeTitle: title,
                           page: pageCount > 1 ? (index, pageCount) : nil, isPlaceholder: false)
    }
}

extension ReviewEntry {
    static func sample(mode: WidgetMode) -> ReviewEntry {
        let account = Account(kind: .github, baseURL: URL(string: "https://github.com")!, authMethod: .personalAccessToken,
                              username: "you", displayName: "You", label: "Work")
        func pr(_ n: Int, _ title: String, _ author: String, kind: ProviderKind = .github, ci: CIStatus = .success, mine: Bool = false) -> PullRequest {
            PullRequest(id: .init(accountID: account.id, project: "acme/\(kind == .github ? "api" : "infra")", number: n), kind: kind,
                        title: title, url: URL(string: "https://example.com")!, author: PRAuthor(login: author, name: author.capitalized),
                        isDraft: false, createdAt: Date().addingTimeInterval(-86400), updatedAt: Date().addingTimeInterval(-3600 * Double(n % 5 + 1)),
                        ciStatus: ci, approvalsCount: n % 3, approvedByMe: false, commentsCount: n % 7,
                        isReviewRequested: !mine, isAssigned: false, isAuthoredByMe: mine)
        }
        let snap = AccountSnapshot(
            account: account, status: .ok(lastSuccess: Date()),
            incoming: [pr(128, "Add retry policy to sync engine", "alice"), pr(131, "Fix flaky pipeline cache", "erin", kind: .gitlab, ci: .running), pr(97, "Upgrade to Swift 6.4", "bob", ci: .failure)],
            outgoing: [pr(140, "Widget timeline provider", "you", mine: true), pr(133, "Liquid glass cards", "you", mine: true)],
            unseenIncomingIDs: [.init(accountID: account.id, project: "acme/api", number: 128)]
        )
        return ReviewEntry(date: Date(), snapshot: Snapshot(accounts: [snap]), fields: .compact, mode: mode,
                           scope: [snap], scopeTitle: "Work", page: (0, 2), isPlaceholder: true)
    }
}
