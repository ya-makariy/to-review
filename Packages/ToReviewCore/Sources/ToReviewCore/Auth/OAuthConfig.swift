import Foundation

/// Public OAuth client ids used for the device flow on github.com and gitlab.com.
///
/// There is no secret here: device flow is designed for public clients. Register
/// your own apps (see README → "OAuth device flow") and paste the ids below, or
/// set them at runtime in Settings → Accounts → OAuth client ids.
public enum OAuthConfig {
    public static let githubClientID = ""
    public static let gitlabClientID = ""

    public static let githubScopes = "repo read:user"
    public static let gitlabScopes = "read_api"

    public static func clientID(for kind: ProviderKind) -> String {
        switch kind {
        case .github: githubClientID
        case .gitlab: gitlabClientID
        }
    }
}
