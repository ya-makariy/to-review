import Foundation

public enum ProviderError: Error, LocalizedError, Sendable {
    /// 401 or 403: bad token or missing scopes.
    case unauthorized
    case rateLimited
    case http(status: Int, body: String)
    case graphQL([String])
    case network(String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "Authentication failed. Check the token and its scopes."
        case .rateLimited: "API rate limit exceeded. Will retry later."
        case .http(let status, _): "Server returned HTTP \(status)."
        case .graphQL(let messages): messages.joined(separator: " ")
        case .network(let detail): "No connection. \(detail)"
        case .invalidResponse(let detail): "Unexpected response: \(detail)"
        }
    }

    /// Errors that mean "fix the account", not "try again later".
    public var isCredentialProblem: Bool {
        if case .unauthorized = self { return true }
        return false
    }
}
