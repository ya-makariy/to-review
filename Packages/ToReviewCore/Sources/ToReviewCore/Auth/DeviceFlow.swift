import Foundation

public enum DeviceFlowError: Error, LocalizedError, Sendable {
    case expired
    case accessDenied
    case server(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .expired: "The code expired before it was entered. Start again."
        case .accessDenied: "Authorization was denied."
        case .server(let message): message
        case .invalidResponse: "Unexpected response from the authorization server."
        }
    }
}

/// What the user must do: open `verificationURL` and type `userCode`.
public struct DeviceAuthorization: Sendable, Hashable {
    public var deviceCode: String
    public var userCode: String
    public var verificationURL: URL
    /// URL with the code pre-filled, when the server provides one.
    public var verificationURLComplete: URL?
    public var expiresAt: Date
    public var interval: TimeInterval
}

/// OAuth 2.0 Device Authorization Grant (RFC 8628) for GitHub and GitLab.
public struct DeviceFlow: Sendable {
    public let kind: ProviderKind
    public let baseURL: URL
    public let clientID: String
    private let session: URLSession

    public init(kind: ProviderKind, baseURL: URL, clientID: String, session: URLSession = .shared) {
        self.kind = kind
        self.baseURL = baseURL
        self.clientID = clientID
        self.session = session
    }

    private var deviceCodeURL: URL {
        switch kind {
        case .github: baseURL.appendingPathComponent("login/device/code")
        case .gitlab: baseURL.appendingPathComponent("oauth/authorize_device")
        }
    }

    private var tokenURL: URL {
        switch kind {
        case .github: baseURL.appendingPathComponent("login/oauth/access_token")
        case .gitlab: baseURL.appendingPathComponent("oauth/token")
        }
    }

    private var scopes: String {
        switch kind {
        case .github: OAuthConfig.githubScopes
        case .gitlab: OAuthConfig.gitlabScopes
        }
    }

    // MARK: Step 1 — request a device code

    public func start() async throws -> DeviceAuthorization {
        let json = try await post(deviceCodeURL, form: ["client_id": clientID, "scope": scopes])
        guard let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let verification = (json["verification_uri"] as? String).flatMap(URL.init(string:)),
              let expiresIn = json["expires_in"] as? Double
        else {
            if let error = json["error_description"] as? String ?? json["error"] as? String {
                throw DeviceFlowError.server(error)
            }
            throw DeviceFlowError.invalidResponse
        }
        let interval = json["interval"] as? Double ?? 5
        return DeviceAuthorization(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURL: verification,
            verificationURLComplete: (json["verification_uri_complete"] as? String).flatMap(URL.init(string:)),
            expiresAt: Date().addingTimeInterval(expiresIn),
            interval: interval
        )
    }

    // MARK: Step 2 — poll until the user approves

    public func waitForToken(_ auth: DeviceAuthorization) async throws -> Credential {
        var interval = auth.interval
        while Date() < auth.expiresAt {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(interval))

            let json = try await post(tokenURL, form: [
                "client_id": clientID,
                "device_code": auth.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])

            if let token = json["access_token"] as? String {
                return Self.credential(from: json, accessToken: token)
            }
            switch json["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "expired_token": throw DeviceFlowError.expired
            case "access_denied": throw DeviceFlowError.accessDenied
            case let other?: throw DeviceFlowError.server(json["error_description"] as? String ?? other)
            case nil: throw DeviceFlowError.invalidResponse
            }
        }
        throw DeviceFlowError.expired
    }

    // MARK: Refresh (GitLab tokens expire after two hours)

    public func refresh(_ credential: Credential) async throws -> Credential {
        guard let refreshToken = credential.refreshToken else { return credential }
        let json = try await post(tokenURL, form: [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
        guard let token = json["access_token"] as? String else {
            throw DeviceFlowError.server(json["error_description"] as? String ?? "Token refresh failed.")
        }
        return Self.credential(from: json, accessToken: token)
    }

    // MARK: Helpers

    private static func credential(from json: [String: Any], accessToken: String) -> Credential {
        let expiresIn = json["expires_in"] as? Double
        return Credential(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            expiresAt: expiresIn.map { Date().addingTimeInterval($0) }
        )
    }

    private func post(_ url: URL, form: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DeviceFlowError.invalidResponse
        }
        return json
    }
}

extension CharacterSet {
    /// `urlQueryAllowed` minus the characters that have meaning inside a form value.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?/:")
        return set
    }()
}
