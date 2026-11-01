import Foundation

/// Tracks which incoming PRs the user has already looked at, and which accounts
/// have completed at least one sync (so we don't notify about the initial backlog).
public struct SeenStore: Sendable {
    private struct State: Codable, Sendable {
        var seen: Set<String> = []
        var syncedAccounts: Set<String> = []
    }

    private let file: JSONFile<State>

    public init(directory: URL = SharedStorage.directoryOrTemporary()) {
        file = JSONFile(directory: directory, name: "seen.json")
    }

    private func load() -> State { file.read() ?? State() }
    private func save(_ state: State) { file.writeOrLog(state) }

    public func seenIDs() -> Set<String> { load().seen }

    public func markSeen(_ ids: some Sequence<PullRequest.ID>) {
        var state = load()
        state.seen.formUnion(ids.map(\.description))
        save(state)
    }

    /// Drop ids that are no longer open so the set doesn't grow forever.
    public func retainOnly(_ ids: some Sequence<PullRequest.ID>) {
        var state = load()
        state.seen.formIntersection(ids.map(\.description))
        save(state)
    }

    public func isSeen(_ id: PullRequest.ID) -> Bool { load().seen.contains(id.description) }

    public func hasCompletedFirstSync(_ accountID: UUID) -> Bool {
        load().syncedAccounts.contains(accountID.uuidString)
    }

    public func markFirstSyncCompleted(_ accountID: UUID) {
        var state = load()
        state.syncedAccounts.insert(accountID.uuidString)
        save(state)
    }

    public func forget(accountID: UUID) {
        var state = load()
        let prefix = accountID.uuidString + "|"
        state.seen = state.seen.filter { !$0.hasPrefix(prefix) }
        state.syncedAccounts.remove(accountID.uuidString)
        save(state)
    }
}
