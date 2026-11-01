import AppKit
import Observation
import ToReviewCore
import WidgetKit

/// Single source of truth for the UI. Owns persistence and the polling loop.
@MainActor
@Observable
final class AppModel {
    private(set) var accounts: [Account]
    var settings: AppSettings {
        didSet {
            settingsStore.save(settings)
            if oldValue.pollInterval != settings.pollInterval { restartPolling() }
            if oldValue.launchAtLogin != settings.launchAtLogin { LaunchAtLogin.apply(enabled: settings.launchAtLogin) }
            if oldValue.hideApprovedByMe != settings.hideApprovedByMe { Task { await refresh() } }
            if oldValue.widgetFields != settings.widgetFields { WidgetCenter.shared.reloadAllTimelines() }
        }
    }
    private(set) var snapshot: Snapshot
    private(set) var isSyncing = false
    /// Set by the delegate; receives PRs that deserve a system notification.
    var onNewIncoming: (([PullRequest]) -> Void)?
    /// Set by the delegate; opens the settings window from SwiftUI views.
    var openSettings: () -> Void = {}

    let settingsStore = SettingsStore()
    let seenStore = SeenStore()
    let tokenStore = TokenStore()
    private let snapshotStore: SnapshotStore
    private let engine: SyncEngine
    private var pollTask: Task<Void, Never>?
    private var consecutiveFailures = 0

    init() {
        settings = settingsStore.loadSettings()
        accounts = settingsStore.loadAccounts()
        snapshotStore = SnapshotStore()
        snapshot = snapshotStore.load()
        engine = SyncEngine(settingsStore: settingsStore, snapshotStore: snapshotStore, seenStore: seenStore, tokenStore: tokenStore)
    }

    // MARK: Derived

    var incomingCount: Int { snapshot.incomingCount }
    var outgoingCount: Int { snapshot.outgoingCount }
    var hasUnseen: Bool { snapshot.hasUnseen }

    func accountSnapshot(_ id: UUID) -> AccountSnapshot? { snapshot.account(id: id) }

    // MARK: Sync

    func refresh(only accountIDs: Set<UUID>? = nil) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let outcome = await engine.sync(previous: snapshot, only: accountIDs)
        snapshot = outcome.snapshot
        consecutiveFailures = snapshot.accounts.contains { !$0.status.isHealthy } ? consecutiveFailures + 1 : 0
        WidgetCenter.shared.reloadAllTimelines()
        if settings.notificationsEnabled, !outcome.newIncoming.isEmpty {
            onNewIncoming?(outcome.newIncoming)
        }
    }

    func markAllSeen() {
        guard snapshot.hasUnseen else { return }
        snapshot = engine.markAllSeen(in: snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.nextDelay()
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func restartPolling() {
        guard pollTask != nil else { return }
        startPolling()
    }

    /// Normal interval, or an exponential backoff (30 s → interval) while something is failing.
    private func nextDelay() -> TimeInterval {
        let normal = settings.pollInterval.seconds
        guard consecutiveFailures > 0 else { return normal }
        let backoff = 30 * pow(2, Double(consecutiveFailures - 1))
        return min(backoff, normal)
    }

    // MARK: Accounts

    func add(_ account: Account, credential: Credential) throws {
        try tokenStore.save(credential, for: account.id)
        accounts.append(account)
        settingsStore.save(accounts)
        Task { await refresh(only: [account.id]) }
    }

    func update(_ account: Account, credential: Credential?) throws {
        if let credential { try tokenStore.save(credential, for: account.id) }
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        settingsStore.save(accounts)
        Task { await refresh(only: [account.id]) }
    }

    func remove(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        settingsStore.save(accounts)
        try? tokenStore.delete(for: account.id)
        seenStore.forget(accountID: account.id)
        snapshot.accounts.removeAll { $0.account.id == account.id }
        Task { await refresh(only: []) } // rewrites the snapshot without the account
    }

    // MARK: Actions

    func open(_ pr: PullRequest) {
        NSWorkspace.shared.open(pr.url)
        seenStore.markSeen([pr.id])
        if let a = snapshot.accounts.firstIndex(where: { $0.account.id == pr.accountID }) {
            snapshot.accounts[a].unseenIncomingIDs.remove(pr.id)
        }
    }
}
