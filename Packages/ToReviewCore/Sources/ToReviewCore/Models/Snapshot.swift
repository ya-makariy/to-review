import Foundation

/// Health of an account as of the last sync attempt.
public enum AccountStatus: Codable, Hashable, Sendable {
    /// Account was added but no sync has completed yet.
    case neverSynced
    case ok(lastSuccess: Date)
    /// The latest sync failed, but we still have data from an earlier successful one.
    case warning(message: String, lastSuccess: Date)
    /// No sync has ever succeeded for this account.
    case error(message: String)

    public var lastSuccess: Date? {
        switch self {
        case .ok(let date), .warning(_, let date): date
        case .neverSynced, .error: nil
        }
    }

    public var errorMessage: String? {
        switch self {
        case .warning(let message, _), .error(let message): message
        case .ok, .neverSynced: nil
        }
    }

    public var isHealthy: Bool {
        if case .ok = self { return true }
        return false
    }
}

/// Everything we know about one account after a sync.
public struct AccountSnapshot: Codable, Hashable, Sendable, Identifiable {
    public var account: Account
    public var status: AccountStatus
    /// Open PRs waiting on the user (reviewer or assignee), already filtered.
    public var incoming: [PullRequest]
    /// Open PRs authored by the user.
    public var outgoing: [PullRequest]
    /// Incoming PR ids the user has not looked at yet.
    public var unseenIncomingIDs: Set<PullRequest.ID>

    public init(
        account: Account,
        status: AccountStatus,
        incoming: [PullRequest] = [],
        outgoing: [PullRequest] = [],
        unseenIncomingIDs: Set<PullRequest.ID> = []
    ) {
        self.account = account
        self.status = status
        self.incoming = incoming
        self.outgoing = outgoing
        self.unseenIncomingIDs = unseenIncomingIDs
    }

    public var id: UUID { account.id }
    public var hasUnseen: Bool { !unseenIncomingIDs.isEmpty }
}

/// The file the app writes to the App Group container and the widget reads.
/// Self-contained on purpose: the widget needs no Keychain or network access.
public struct Snapshot: Codable, Sendable, Hashable {
    public static let currentVersion = 1

    public var version: Int
    public var generatedAt: Date
    public var accounts: [AccountSnapshot]

    public init(generatedAt: Date = Date(), accounts: [AccountSnapshot] = []) {
        self.version = Self.currentVersion
        self.generatedAt = generatedAt
        self.accounts = accounts
    }

    public static let empty = Snapshot(generatedAt: .distantPast, accounts: [])

    public var incomingCount: Int { accounts.reduce(0) { $0 + $1.incoming.count } }
    public var outgoingCount: Int { accounts.reduce(0) { $0 + $1.outgoing.count } }
    public var hasUnseen: Bool { accounts.contains { $0.hasUnseen } }

    public var allIncoming: [PullRequest] {
        accounts.flatMap(\.incoming).sorted { $0.updatedAt > $1.updatedAt }
    }

    public var allOutgoing: [PullRequest] {
        accounts.flatMap(\.outgoing).sorted { $0.updatedAt > $1.updatedAt }
    }

    public func account(id: UUID) -> AccountSnapshot? {
        accounts.first { $0.account.id == id }
    }

    /// Worst status across accounts, for the global banner.
    public var hasErrors: Bool {
        accounts.contains { if case .error = $0.status { true } else { false } }
    }

    public var hasWarnings: Bool {
        accounts.contains { if case .warning = $0.status { true } else { false } }
    }
}
