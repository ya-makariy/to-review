import Foundation

/// Who the token belongs to, returned by `validate`.
public struct ProviderIdentity: Sendable, Hashable {
    public var login: String
    public var name: String?
    public var avatarURL: URL?

    public init(login: String, name: String? = nil, avatarURL: URL? = nil) {
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
    }
}

/// One hosting service. Implementations are stateless value types bound to an account + token.
public protocol GitProvider: Sendable {
    /// Checks the token and returns the identity it belongs to.
    static func validate(baseURL: URL, token: String, session: URLSession) async throws -> ProviderIdentity

    /// All open PRs relevant to the user with `isReviewRequested` / `isAssigned` /
    /// `isAuthoredByMe` flags set. Deduplicated by `PullRequest.ID`; not yet filtered.
    func fetchPullRequests() async throws -> [PullRequest]
}

public enum ProviderFactory {
    public static func make(account: Account, token: String, session: URLSession = .shared) -> any GitProvider {
        switch account.kind {
        case .github: GitHubProvider(account: account, token: token, session: session)
        case .gitlab: GitLabProvider(account: account, token: token, session: session)
        }
    }

    public static func validate(kind: ProviderKind, baseURL: URL, token: String, session: URLSession = .shared) async throws -> ProviderIdentity {
        switch kind {
        case .github: try await GitHubProvider.validate(baseURL: baseURL, token: token, session: session)
        case .gitlab: try await GitLabProvider.validate(baseURL: baseURL, token: token, session: session)
        }
    }
}

extension Array where Element == PullRequest {
    /// Merges duplicates (same PR found by several searches) by OR-ing their role flags.
    func mergedByID() -> [PullRequest] {
        var byID: [PullRequest.ID: PullRequest] = [:]
        var order: [PullRequest.ID] = []
        for pr in self {
            if var existing = byID[pr.id] {
                existing.isReviewRequested = existing.isReviewRequested || pr.isReviewRequested
                existing.isAssigned = existing.isAssigned || pr.isAssigned
                existing.isAuthoredByMe = existing.isAuthoredByMe || pr.isAuthoredByMe
                byID[pr.id] = existing
            } else {
                byID[pr.id] = pr
                order.append(pr.id)
            }
        }
        return order.compactMap { byID[$0] }
    }
}
