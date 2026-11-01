import Foundation

/// Result of one full sync pass.
public struct SyncOutcome: Sendable {
    public var snapshot: Snapshot
    /// Incoming PRs that appeared since the previous pass on accounts that had
    /// already completed a sync — the ones worth a system notification.
    public var newIncoming: [PullRequest]
}

/// Fetches every enabled account, classifies PRs, tracks what's new, and writes the snapshot.
/// Only the app runs this; the widget just reads the resulting file.
public struct SyncEngine: Sendable {
    private let settingsStore: SettingsStore
    private let snapshotStore: SnapshotStore
    private let seenStore: SeenStore
    private let tokenStore: TokenStore
    private let session: URLSession

    public init(
        settingsStore: SettingsStore = SettingsStore(),
        snapshotStore: SnapshotStore,
        seenStore: SeenStore = SeenStore(),
        tokenStore: TokenStore = TokenStore(),
        session: URLSession = .shared
    ) {
        self.settingsStore = settingsStore
        self.snapshotStore = snapshotStore
        self.seenStore = seenStore
        self.tokenStore = tokenStore
        self.session = session
    }

    /// Syncs all enabled accounts (or just `accountIDs` when given) and persists the snapshot.
    public func sync(previous: Snapshot, only accountIDs: Set<UUID>? = nil) async -> SyncOutcome {
        let settings = settingsStore.loadSettings()
        let accounts = settingsStore.loadAccounts().filter(\.isEnabled)

        let results = await withTaskGroup(of: (UUID, Result<[PullRequest], Error>).self) { group in
            for account in accounts where accountIDs?.contains(account.id) ?? true {
                group.addTask { (account.id, await fetch(account: account, settings: settings)) }
            }
            var dict: [UUID: Result<[PullRequest], Error>] = [:]
            for await (id, result) in group { dict[id] = result }
            return dict
        }

        let now = Date()
        let seen = seenStore.seenIDs()
        var newIncoming: [PullRequest] = []
        var accountSnapshots: [AccountSnapshot] = []

        for account in accounts {
            let cached = previous.account(id: account.id)
            guard let result = results[account.id] else {
                // Not part of this partial sync: carry the previous state over.
                if let cached { accountSnapshots.append(cached) }
                else { accountSnapshots.append(AccountSnapshot(account: account, status: .neverSynced)) }
                continue
            }

            switch result {
            case .success(let prs):
                let classified = Self.classify(prs, settings: settings)
                let unseen = Set(classified.incoming.map(\.id).filter { !seen.contains($0.description) })
                if seenStore.hasCompletedFirstSync(account.id) {
                    let previousIDs = Set(cached?.incoming.map(\.id) ?? [])
                    newIncoming += classified.incoming.filter { unseen.contains($0.id) && !previousIDs.contains($0.id) }
                } else {
                    // First successful sync: the existing backlog is not "new".
                    seenStore.markSeen(classified.incoming.map(\.id))
                    seenStore.markFirstSyncCompleted(account.id)
                }
                accountSnapshots.append(AccountSnapshot(
                    account: account,
                    status: .ok(lastSuccess: now),
                    incoming: classified.incoming,
                    outgoing: classified.outgoing,
                    unseenIncomingIDs: seenStore.hasCompletedFirstSync(account.id) ? unseen : []
                ))

            case .failure(let error):
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if let cached, let lastSuccess = cached.status.lastSuccess {
                    accountSnapshots.append(AccountSnapshot(
                        account: account,
                        status: .warning(message: message, lastSuccess: lastSuccess),
                        incoming: cached.incoming,
                        outgoing: cached.outgoing,
                        unseenIncomingIDs: cached.unseenIncomingIDs
                    ))
                } else {
                    accountSnapshots.append(AccountSnapshot(account: account, status: .error(message: message)))
                }
            }
        }

        // Keep the seen-set bounded to PRs that are still open somewhere.
        seenStore.retainOnly(accountSnapshots.flatMap { $0.incoming.map(\.id) })

        let snapshot = Snapshot(generatedAt: now, accounts: accountSnapshots)
        do { try snapshotStore.save(snapshot) } catch {
            SharedStorage.log.error("Snapshot save failed: \(error.localizedDescription, privacy: .public)")
        }
        return SyncOutcome(snapshot: snapshot, newIncoming: newIncoming.sorted { $0.updatedAt > $1.updatedAt })
    }

    /// Marks every incoming PR as seen and rewrites the snapshot without dots.
    public func markAllSeen(in snapshot: Snapshot) -> Snapshot {
        var updated = snapshot
        for index in updated.accounts.indices {
            seenStore.markSeen(updated.accounts[index].incoming.map(\.id))
            updated.accounts[index].unseenIncomingIDs = []
        }
        try? snapshotStore.save(updated)
        return updated
    }

    // MARK: - Pieces

    private func fetch(account: Account, settings: AppSettings) async -> Result<[PullRequest], Error> {
        do {
            var credential = try tokenStore.credential(for: account.id)
            if credential.needsRefresh(), let clientID = settings.oauthClientID(for: account.kind) {
                let flow = DeviceFlow(kind: account.kind, baseURL: account.baseURL, clientID: clientID, session: session)
                credential = try await flow.refresh(credential)
                try tokenStore.save(credential, for: account.id)
            }
            let provider = ProviderFactory.make(account: account, token: credential.accessToken, session: session)
            let prs = try await provider.fetchPullRequests()
            await AvatarCache().cacheAvatars(for: prs, account: account, token: credential.accessToken, session: session)
            return .success(prs)
        } catch {
            return .failure(error)
        }
    }

    public struct Classified: Sendable {
        public var incoming: [PullRequest]
        public var outgoing: [PullRequest]
    }

    /// Incoming: open, not draft, not mine, requested or assigned, and (optionally) not yet approved by me.
    /// Outgoing: authored by me, drafts included.
    public static func classify(_ prs: [PullRequest], settings: AppSettings) -> Classified {
        let incoming = prs.filter { pr in
            (pr.isReviewRequested || pr.isAssigned)
                && !pr.isAuthoredByMe
                && !pr.isDraft
                && !(settings.hideApprovedByMe && pr.approvedByMe)
        }
        let outgoing = prs.filter(\.isAuthoredByMe)
        return Classified(
            incoming: incoming.sorted { $0.updatedAt > $1.updatedAt },
            outgoing: outgoing.sorted { $0.updatedAt > $1.updatedAt }
        )
    }
}
